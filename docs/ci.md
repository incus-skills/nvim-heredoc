# Continuous integration design

## Purpose

CI must validate the heredoc implementation at the same independent layers as the design contract. A green result from one layer must not stand in for another: a scanner can identify a region correctly while an editor integration corrupts bytes, and a visually correct buffer can still deliver the wrong payload to a shell.

The initial CI design separates four validation layers:

1. **Core scanner and buffer behaviour** — deterministic Lua/Neovim tests, independent of LazyVim.
2. **Shell delivery** — execute fixtures with Bash, a POSIX shell, and Zsh; compare exact payload bytes.
3. **Formatter behaviour** — run the supported `shfmt -i 0 -p` invocation against Bash and POSIX `sh` fixtures and compare payload bytes.
4. **LazyVim integration** — exercise the plugin in a containerised, headless LazyVim environment with the relevant plugins present.

## Workflow shape

The initial workflow is `.github/workflows/test.yml`. It currently runs three independent jobs on pushes to `main`, pull requests, and manual dispatch: `core`, `shell-delivery`, and `formatter`. The `lazyvim-integration` job is intentionally deferred until the plugin integration and its test command exist. It must be added as a separate job so failures identify distribution/plugin integration rather than being conflated with scanner or shell-semantic failures.

The first three jobs use a lightweight `ubuntu-24.04` hosted runner. They do not require bootstrapping a full LazyVim installation. The current workflow installs Lua 5.1, Zsh, and shfmt from the runner's Ubuntu package repositories and prints their runtime versions. This is an initial repeatable baseline, not yet a fully locked toolchain: package versions should be pinned once the supported version floor is selected.

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

These commands should also be runnable locally where dependencies are available. CI invokes the same commands rather than containing a second implementation of test logic. The current commands are `bash tests/run-core.sh`, `bash tests/run-shell-delivery.sh`, and `bash tests/formatter/test-shfmt.sh`.

## Container boundary

The container is an integration test environment, not the product runtime and not a requirement for users installing the plugin. It exists to make LazyVim and its selected plugins reproducible. The scanner and shell-delivery tests should remain runnable without it.

Do not add a large prebuilt container dependency before the test commands and plugin versions are known. Start with a repository-owned Dockerfile when the integration test can specify its exact runtime requirements. This avoids allowing a container image or a particular LazyVim release to dictate the scanner architecture.

## Reporting

Keep job names aligned with the validation layers: `core`, `shell-delivery`, `formatter`, and `lazyvim-integration`. Preserve separate reports so a failure identifies which contract was violated.

The workflow is not complete merely because it parses or runs. It must be exercised against at least one known passing fixture and a deliberately failing fixture for each test command, demonstrating that regressions produce a failing job. The initial workflow has completed two successful full runs. The latest includes expanded uncertainty/arithmetic/space-indentation scanner cases: GitHub Actions run [43150889806](https://github.com/incus-skills/nvim-heredoc/actions/runs/43150889806). The core scanner, shell-delivery, and formatter jobs all passed. The observed runtime versions were Lua 5.1.5, Bash 5.2.21, Zsh 5.9, and shfmt 3.8.0; Dash was present and passed the payload comparison. The formatter test exercises the configured `shfmt -i 0 -p` invocation against a Bash fixture and a POSIX-shell-subset fixture, then compares actual shell output before and after formatting. It does not establish preservation for every heredoc grammar or payload shape.

The initial formatter test command combined `-p` with `-ln`, which shfmt rejects. The command was corrected to use the configured `-i 0 -p` invocation without `-ln`; the successful run therefore uses shfmt's default language mode for both fixtures. This is a test-harness correction, not evidence of a formatter payload defect.
