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

The plugin has no user-facing setup options at present. The empty `opts = {}`
field is retained as the conventional lazy.nvim setup entrypoint; the plugin
uses its fixed supported-filetype set and attaches to matching buffers.

## Semantics that constrain the implementation

A shell `<<-` heredoc removes leading **TAB bytes** from body lines and from the terminating delimiter. It does not remove leading spaces.

The implementation distinguishes:

- **Structural indentation:** leading TAB bytes used to nest the opener and delimiter in shell code and removed by `<<-`.
- **Content indentation:** payload whitespace, especially leading spaces, which must remain unchanged.

Leading TAB bytes in the body are also stripped by the shell. The editor therefore cannot promise to preserve them as payload indentation. No special values for `expandtab`, `tabstop`, `softtabstop`, or `shiftwidth` are required to position the opener: the earlier need to force those options was a workaround for an older column-zero opener implementation, and is obsolete. The plugin does not set these options.

Ordinary `<<` heredocs and `<<<` here-strings are outside the managed scope and must remain untouched.

## Architecture

**The interactive editing contract is Return-local, not document-global.** The plugin acts when the user presses Return after completing a managed <<- opener. That event commits to the new heredoc: the plugin inserts the matching closer immediately, placing it within the available enclosing shell structure (for example, before an existing function-closing brace). The inserted closer establishes the end of this heredoc's lexical input scope. Body text between the opener and closer is payload, even when it resembles another shell heredoc opener. The plugin does not need a document-wide ledger of other heredocs, opener identities, or competing future terminators to establish this scope.

The lexical scanner remains a bounded helper for recognising the current opener, delimiter, mode, and safe local boundaries. It is not a mandate to reconstruct the entire document's heredoc ownership or shell structure. Existing shell indentation machinery remains responsible for ordinary function and compound-command indentation wherever it can provide that context. Do not duplicate it with a general structural parser merely to place this local closer.

An established heredoc body is also a lexical zone for syntax representation: the containing shell parser must not claim embedded payload constructs (including an inner heredoc `EOF`) as active syntax of the outer shell document. The scanner-established body boundary is authoritative for both editing and future syntax presentation. The current Tree-sitter Bash interpretation of an inner `EOF` as an outer-shell construct is a known mismatch with this policy. How payloads are eventually represented—contained-language parsing/injection or opaque content—remains future work; deferring that choice does not defer the boundary requirement.

Typing the opener alone does not commit a closer; Return does. Existing-buffer recovery and other editing paths must not silently turn this into a general opener-time or document-wide tracking system.

Paste handling must operate on the complete changed range and preserve existing bytes. If the range or region is ambiguous, the safe behaviour is to leave the text unchanged.

Formatting is separate from interactive editing. `shfmt` is for Bash and POSIX `sh` only, not Zsh. Its effect on heredoc payload bytes must be tested rather than assumed.

## Future development context

The adopted lexical-zone policy and remaining embedded-payload design questions are recorded in [future development context](docs/future-development-context.md). The current syntax-presentation mismatch and its bounded implementation work are tracked in [Task 002](tasks/active/002-syntax-presentation-lexical-zone-containment.md). Language identification, diagnostics/completion, and formatter isolation remain separate future integrations.

## Current status

- Repository initialisation complete.
- Architecture and indentation invariants recorded in [the design contract](docs/design.md).
- A conservative Lua scanner, pure structural closer/paste helpers, and Neovim buffer integration with changed-range tracking are present under `lua/` and `tests/`.
- [The CI workflow](.github/workflows/test.yml) runs core, headless buffer integration, shell-delivery, formatter, and pinned LazyVim/plugin coexistence jobs.
- The LazyVim integration harness now loads the repository as a local lazy.nvim plugin using `dir`, `ft`, and `opts`, exercising the same setup lifecycle as the documented installation spec. See [the CI design](docs/ci.md).
- [Task 001](tasks/active/001-core-design-and-prototype.md) remains active. Its governing direction is the Return-local bounded-scope contract in [the design contract](docs/design.md); existing tests remain regression evidence, not a requirement to expand into a general shell parser or document-wide heredoc tracker.

