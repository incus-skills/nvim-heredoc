# Task 002 — Initial installation and live replacement

**Status:** active — entrypoint and documented installation path added; live workstation verification pending  
**Priority:** immediate  
**Scope:** make the tested implementation installable as a Neovim plugin and support a reversible replacement of the previous shell ftplugins. Do not add a standalone provisioning framework or broaden scanner grammar in this task.

## Objective

Allow the user to replace the previous `after/ftplugin/bash.lua`, `sh.lua`, and `zsh.lua` implementation with the repository's shared Lua scanner and buffer integration, then verify behaviour in the actual Neovim 0.12.4/LazyVim environment.

## Work completed

- Added `plugin/nvim-heredoc.lua` as the runtime entrypoint. It guards against duplicate loading and calls `require("nvim-heredoc").setup()`.
- Updated the pinned LazyVim fixture and its negative control to load through the runtime entrypoint rather than calling `setup()` directly.
- Added [installation and replacement instructions](../../docs/installation.md) for lazy.nvim, including backup/disable of the previous ftplugins, live checks, shell-delivery verification, and rollback.
- Added an installation link and updated status in the README.
- The repository still has no standalone installer script. The initial method intentionally uses the plugin manager and explicit reversible file moves rather than introducing a second code-copying/provisioning mechanism.

## Remaining work

1. Run the updated five-job CI workflow and confirm the runtime entrypoint is exercised successfully in the LazyVim fixture.
2. Install from the repository in the user's actual LazyVim environment.
3. Back up and disable the previous ftplugins without losing unrelated filetype configuration.
4. Verify startup loading, Bash/`sh`/Zsh attachment, automatic closer insertion, changed-range indentation, ordinary-heredoc non-interference, and shell-delivered payload bytes.
5. Record the actual Neovim/LazyVim/plugin revisions and any differences from the pinned fixture.
6. Correct any implementation or installation defects exposed by live testing; do not suppress unrelated completion/pair/formatting behaviour without evidence.
7. Keep this task active until the user confirms the replacement operates as intended.

## Acceptance criteria

- The repository is loadable through a normal lazy.nvim plugin specification without a user-written `setup()` callback.
- The runtime entrypoint is idempotent.
- The old implementation can be disabled reversibly with a preserved backup.
- Installation and rollback instructions do not overwrite unrelated user configuration.
- The live LazyVim environment demonstrates the expected editing behaviour and unchanged shell payload.
- The old implementation is no longer active when the new plugin is active.
- All claims distinguish CI fixture evidence from live workstation evidence.

## Boundaries

- Do not add a Go/parser runtime dependency.
- Do not treat the pinned LazyVim fixture as a substitute for the live workstation.
- Do not delete the legacy backup after migration.
- Do not mark Task 001 complete solely because the installation path exists; its scanner/editing limits remain independently tracked.
