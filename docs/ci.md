# Continuous integration design

## Purpose

CI must validate the heredoc implementation at the same independent layers as the design contract. A green result from one layer must not stand in for another: a scanner can identify a region correctly while an editor integration corrupts bytes, and a visually correct buffer can still deliver the wrong payload to a shell.

The CI workflow reports five validation layers independently:

1. **Core scanner** — deterministic Lua tests, independent of Neovim and LazyVim.
2. **Neovim buffer integration** — headless editing and changed-range tests, independent of LazyVim.
3. **Shell delivery** — execute fixtures with Bash, a POSIX shell, and Zsh; compare exact payload bytes.
4. **Formatter behaviour** — run the supported `shfmt -i 0 -p` invocation against Bash and POSIX `sh` fixtures and compare payload bytes.
5. **LazyVim integration** — exercise the plugin in a containerised, headless LazyVim environment with the relevant plugins present.

## Workflow shape

The workflow is `.github/workflows/test.yml`. It runs five independent jobs on pushes to `main`, pull requests, and manual dispatch: `core`, `buffer-integration`, `shell-delivery`, `formatter`, and `lazyvim-integration`. The LazyVim job is separate so failures identify distribution/plugin integration rather than being conflated with scanner or shell-semantic failures.

The core, shell-delivery, and formatter jobs use a lightweight `ubuntu-24.04` hosted runner. The buffer-integration job also uses that runner but installs the distribution's Neovim package (observed version 0.9.5); it does not bootstrap LazyVim. The current workflow installs Lua 5.1, Zsh, and shfmt from the runner's Ubuntu package repositories and prints their runtime versions. This is an initial repeatable baseline, not yet a fully locked toolchain: package versions should be pinned once the supported version floor is selected.

The LazyVim job builds and runs the repository-owned image in `ci/lazyvim/Dockerfile`. Its revision manifest is `ci/lazyvim/versions.env`; it pins Neovim 0.12.4 and the exact LazyVim, lazy.nvim, mini.pairs, blink.cmp, and conform.nvim commits observed in the supplied workstation inventory. The plugin under test is copied from the checked-out commit into the image, not fetched from a moving branch.

This first fixture is deliberately controlled rather than a clone of the user's entire LazyVim configuration. It loads the pinned LazyVim core and the selected plugin checkouts directly, applies the relevant LazyVim mini.pairs defaults, configures Blink with its normal fuzzy-backend selection and a buffer source, and configures Conform with the observed `shfmt` assignments. It does not import the full LazyVim starter plugin graph, the user's private configuration, or the legacy `after/ftplugin` heredoc implementation. The fixture sends a real insert-mode quote through mini.pairs in ordinary shell code and a managed heredoc body, and triggers Blink's actual buffer-source completion menu from inside a managed heredoc body, asserting that it becomes visible with candidates. Passing this fixture is evidence for the exercised core/plugin combination only, not a claim of compatibility with every LazyVim plugin or user override.

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

These commands should also be runnable locally where dependencies are available. CI invokes the same commands rather than containing a second implementation of test logic. The current commands are `bash tests/run-core.sh`, `bash tests/run-nvim.sh`, `bash tests/run-shell-delivery.sh`, `bash tests/formatter/test-shfmt.sh`, and `bash tests/run-lazyvim.sh` (the last runs inside `ci/lazyvim/Dockerfile`).

## Positive and negative controls

The stable commands each include a deliberate negative control:

- `bash tests/run-core.sh`: the scanner must not classify an ordinary `<<` heredoc as managed.
- `bash tests/run-nvim.sh`: the buffer integration must not edit an ordinary `<<` heredoc.
- `bash tests/run-shell-delivery.sh`: `<<-` must not deliver the leading TAB byte.
- `bash tests/formatter/test-shfmt.sh`: `shfmt` must not change the executed heredoc payload.
- `bash tests/run-lazyvim.sh`: the plugin must not edit an ordinary `<<` heredoc with the pinned plugin environment loaded.

`tests/expect-failure.sh` checks both non-zero exit and a fixture-specific assertion marker. A setup error or unrelated crash is not accepted as a successful negative control.

## Latest negative-control validation

All five jobs passed with the contract-specific negative controls enabled in [workflow run 43196642359](https://github.com/incus-skills/nvim-heredoc/actions/runs/43196642359). Each job log contains its expected `PASS: ... negative control rejected the expected forbidden behaviour` line:

- Core scanner: ordinary `<<` remains outside managed regions.
- Neovim buffer integration: ordinary `<<` remains unchanged.
- Shell delivery: `<<-` removes the leading TAB byte.
- Formatter: `shfmt -i 0 -p` preserves the tested delivered payload.
- LazyVim integration: the plugin leaves ordinary `<<` unchanged with the pinned plugin environment loaded.

These controls are contract-specific negative assertions, not arbitrary failing commands. The wrapper also checks the expected marker so dependency/setup failures cannot be mistaken for a successful negative control.

## Container boundary

The container is an integration test environment, not the product runtime and not a requirement for users installing the plugin. It exists to make LazyVim and its selected plugins reproducible. The scanner and shell-delivery tests should remain runnable without it.

The container is an integration test environment, not the product runtime and not a requirement for users installing the plugin. It is intentionally independent of the user's old shell ftplugins. Keep the scanner and shell-delivery tests runnable without it.

## Reporting

Keep job names aligned with the validation layers: `core`, `buffer-integration`, `shell-delivery`, `formatter`, and `lazyvim-integration`. Preserve separate reports so a failure identifies which contract was violated.

Each test command now runs a positive fixture and a negative control. The negative controls assert a deliberately forbidden outcome and are wrapped by `tests/expect-failure.sh`, which requires the assertion to fail for its specific marker. If the forbidden outcome starts occurring, the negative fixture unexpectedly succeeds and the wrapper fails the CI job. Controls cover ordinary-heredoc classification (core), ordinary-heredoc mutation (buffer and LazyVim integration), leading-TAB removal by `<<-` (shell delivery), and payload preservation by shfmt (formatter). This checks each layer's own contract rather than merely testing generic non-zero exit propagation. The initial three-job workflow passed all tests in run [43151269417](https://github.com/incus-skills/nvim-heredoc/actions/runs/43151269417). After adding the first Neovim buffer integration, all four jobs passed in run [43151626549](https://github.com/incus-skills/nvim-heredoc/actions/runs/43151626549). The latest run [43153320144](https://github.com/incus-skills/nvim-heredoc/actions/runs/43153320144) passed all four jobs after adding empty quoted delimiter coverage to the scanner and shell-delivery tests. The buffer job used Neovim 0.9.5. The observed runtime versions were Lua 5.1.5, Bash 5.2.21, Zsh 5.9, and shfmt 3.8.0; Dash was present and passed the payload comparison. The formatter test exercises the configured `shfmt -i 0 -p` invocation against a Bash fixture and a POSIX-shell-subset fixture, then compares actual shell output before and after formatting. It does not establish preservation for every heredoc grammar or payload shape.

The initial formatter test command combined `-p` with `-ln`, which shfmt rejects. The command was corrected to use the configured `-i 0 -p` invocation without `-ln`; the successful run therefore uses shfmt's default language mode for both fixtures. This is a test-harness correction, not evidence of a formatter payload defect.
