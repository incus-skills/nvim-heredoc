# nvim-heredoc

Reliable shell heredoc editing support for Neovim.

The initial integration target is LazyVim, but the editing logic should remain usable independently of a particular Neovim distribution.

## Project objective

Provide predictable editing support for shell `<<-` (tab-stripping) heredocs:

- Insert a matching closing delimiter automatically.
- Keep the opener and closing delimiter structurally indented within surrounding shell code.
- Preserve relative indentation and existing bytes when multiline content is pasted.
- Avoid changing ordinary `<<` heredocs and here-strings (`<<<`).
- Work in Bash, POSIX `sh`, and Zsh buffers.
- Coexist with the user's existing completion, pair, indentation, and formatting configuration.

## Installation

See [installation and replacement](docs/installation.md) for the provisioning-script installation, replacement semantics, live verification, and removal procedure.

## Semantics that constrain the implementation

A shell `<<-` heredoc removes leading **TAB bytes** from body lines and from the terminating delimiter. It does not remove leading spaces.

The implementation distinguishes:

- **Structural indentation:** leading TAB bytes used to nest the opener and delimiter in shell code and removed by `<<-`.
- **Content indentation:** payload whitespace, especially leading spaces, which must remain unchanged.

Leading TAB bytes in the body are also stripped by the shell. The editor therefore cannot promise to preserve them as payload indentation. The provisioned filetype entrypoints set `expandtab = false`, `tabstop = 2`, `softtabstop = 0`, and `shiftwidth = 2` for Bash, POSIX `sh`, and Zsh. This is required for the intended literal-TAB editing model; the two-column tab display is only cosmetic.

Ordinary `<<` heredocs and `<<<` here-strings are outside the managed scope and must remain untouched.

## Architecture

A shared, buffer-independent Lua lexical scanner is the authority for heredoc regions in all three filetypes. Treesitter may provide optional structural assistance, but is not a dependency. Editing, closer insertion, paste handling, and later plugin integrations consume the same region model; they must not independently infer the active heredoc from the nearest preceding opener.

Paste handling must operate on the complete changed range and preserve existing bytes. If the range or region is ambiguous, the safe behaviour is to leave the text unchanged.

Formatting is separate from interactive editing. `shfmt` is for Bash and POSIX `sh` only, not Zsh. Its effect on heredoc payload bytes must be tested rather than assumed.

## Current status

- Repository initialisation complete.
- Architecture and indentation invariants recorded in [the design contract](docs/design.md).
- A conservative Lua scanner, pure structural closer/paste helpers, and Neovim buffer integration with changed-range tracking are present under `lua/` and `tests/`. The current live-editing implementation reserves a closer after the active first body line and applies changed-range indentation during Insert mode; the new interaction regression is committed, with CI verification pending. Interfaces and current limits are documented in [scanner.md](docs/scanner.md).
- [The CI workflow](.github/workflows/test.yml) runs core, headless buffer integration, shell-delivery, formatter, and pinned LazyVim/plugin coexistence jobs. The first five-job run passed in [run 43175124220](https://github.com/incus-skills/nvim-heredoc/actions/runs/43175124220). The LazyVim fixture uses the observed Neovim 0.12.4 and pinned LazyVim, mini.pairs, blink.cmp, conform.nvim, and lazy.nvim revisions; see [the CI design](docs/ci.md) and [plugin compatibility inventory](docs/plugin-compatibility.md).
- [Task 001](tasks/active/001-core-design-and-prototype.md) remains active: expand and validate shell grammar coverage, stress-test editing/paste behaviour, extend plugin interaction coverage, and complete deliberate-failure regression checks.
- The pinned LazyVim fixture validates the selected plugin revisions in a controlled headless environment; it is not the user's full LazyVim configuration. The repository now has a provisioning-script installation path that installs the tested Lua modules and generates per-filetype entrypoints. Live operation in the user's configuration remains to be verified.

