# Continuous integration design

## Purpose

CI must validate the heredoc implementation at the same independent layers as the design contract. A green result from one layer must not stand in for another: a scanner can identify a region correctly while an editor integration corrupts bytes, and a visually correct buffer can still deliver the wrong payload to a shell.

The initial CI design separates four validation layers:

1. **Core scanner and buffer behaviour** — deterministic Lua/Neovim tests, independent of LazyVim.
2. **Shell delivery** — execute fixtures with Bash, a POSIX shell, and Zsh; compare exact payload bytes.
3. **Formatter behaviour** — run the supported `shfmt -i 0 -p` invocation against Bash and POSIX `sh` fixtures and compare payload bytes.
4. **LazyVim integration** — exercise the plugin in a containerised, headless LazyVim environment with the relevant plugins present.

## Workflow shape

The intended workflow is `.github/workflows/test.yml`. The core, shell-delivery, and formatter jobs should run on every push and pull request. LazyVim integration should be a separate job so failures identify distribution/plugin integration rather than being conflated with scanner or shell-semantic failures. It should run on pull requests and pushes to the primary branch; a manual trigger may also be useful for diagnosing dependency changes.

The first three jobs should use a lightweight hosted runner. They must not require bootstrapping a full LazyVim installation.

The LazyVim job should build and run a repository-owned container image from `ci/Dockerfile` (or use an equivalently reproducible pinned image once one exists). The container should provide a headless Neovim runtime and a controlled LazyVim/plugin configuration. The plugin under test should be mounted or copied into that environment from the checked-out commit, not fetched from an unrelated moving branch.

## Reproducibility and dependency policy

- Pin Neovim, LazyVim, and integration-plugin revisions or versions used by the integration environment. Avoid floating `latest` tags and unbounded plugin updates.
- Record the selected versions and update procedure alongside the container definition.
- Keep the core test path independent of LazyVim and optional plugins.
- Install or select explicit versions of Bash, the POSIX shell used by the tests, Zsh, and `shfmt`; record the actual versions in CI output.
- A missing shell or formatter must produce an explicit skip or job failure according to the test's declared requirement. It must not silently reduce coverage.
- Do not use CI success as evidence for shells, versions, or plugin configurations that were not actually exercised.

## Test interfaces to establish before the workflow

The implementation should define stable commands before the workflow is authored:

- A core test command that exits non-zero on any scanner, region, or buffer-editing regression.
- A shell-delivery command that executes fixtures and compares captured payloads byte-for-byte.
- A formatter test command that runs the supported formatter and compares payloads before and after formatting.
- A headless LazyVim integration command that loads the checked-out plugin and exercises only verified integration APIs.

These commands should also be runnable locally where dependencies are available. CI should invoke the same commands rather than contain a second implementation of test logic.

## Container boundary

The container is an integration test environment, not the product runtime and not a requirement for users installing the plugin. It exists to make LazyVim and its selected plugins reproducible. The scanner and shell-delivery tests should remain runnable without it.

Do not add a large prebuilt container dependency before the test commands and plugin versions are known. Start with a repository-owned Dockerfile when the integration test can specify its exact runtime requirements. This avoids allowing a container image or a particular LazyVim release to dictate the scanner architecture.

## Reporting

Keep job names aligned with the validation layers: `core`, `shell-delivery`, `formatter`, and `lazyvim-integration`. Preserve separate reports so a failure identifies which contract was violated.

The workflow is not complete merely because it parses or runs. It must be exercised against at least one known passing fixture and a deliberately failing fixture for each test command, demonstrating that regressions produce a failing job.
