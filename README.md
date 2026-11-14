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

Install with lazy.nvim using the normal plugin specification:

```lua
{
  "incus-skills/nvim-heredoc",
  ft = { "bash", "sh", "zsh" },
  opts = {},
}
```

lazy.nvim loads the plugin on the first supported filetype event and calls
`require("nvim-heredoc").setup({})`. The plugin then attaches to supported
buffers without requiring generated user ftplugins or copied Lua modules.

The existing [provisioning instructions](docs/installation.md) are retained
temporarily while the development harness and installation transition are
updated. They describe the legacy provisioning path and are not the recommended
installation method.

## Semantics that constrain the implementation

A shell `<<-` heredoc removes leading **TAB bytes** from body lines and from the terminating delimiter. It does not remove leading spaces.

The implementation distinguishes:

- **Structural indentation:** leading TAB bytes used to nest the opener and delimiter in shell code and removed by `<<-`.
- **Content indentation:** payload whitespace, especially leading spaces, which must remain unchanged.

Leading TAB bytes in the body are also stripped by the shell. The editor therefore cannot promise to preserve them as payload indentation. The plugin must work with the buffer's existing indentation settings; it must not silently change `expandtab`, `tabstop`, `softtabstop`, or `shiftwidth`.

Ordinary `<<` heredocs and `<<<` here-strings are outside the managed scope and must remain untouched.

## Architecture

A shared, buffer-independent Lua lexical scanner is the authority for heredoc regions in all three filetypes. Treesitter may provide optional structural assistance, but is not a dependency. Editing, closer insertion, paste handling, and later plugin integrations consume the same region model; they must not independently infer the active heredoc from the nearest preceding opener.

Paste handling must operate on the complete changed range and preserve existing bytes. If the range or region is ambiguous, the safe behaviour is to leave the text unchanged.

Formatting is separate from interactive editing. `shfmt` is for Bash and POSIX `sh` only, not Zsh. Its effect on heredoc payload bytes must be tested rather than assumed.

## Current status

- Repository initialisation complete.
- Architecture and indentation invariants recorded in [the design contract](docs/design.md).
- A conservative Lua scanner, pure structural closer/paste helpers, and Neovim buffer integration with changed-range tracking are present under `lua/` and `tests/`.
- [The CI workflow](.github/workflows/test.yml) runs core, headless buffer integration, shell-delivery, formatter, and pinned LazyVim/plugin coexistence jobs.
- The LazyVim integration harness now loads the repository as a local lazy.nvim plugin using `dir`, `ft`, and `opts`, exercising the same setup lifecycle as the documented installation spec. See [the CI design](docs/ci.md).
- [Task 001](tasks/active/001-core-design-and-prototype.md) remains active: expand and validate shell grammar coverage, stress-test editing/paste behaviour, extend plugin interaction coverage, and complete deliberate-failure regression checks.

