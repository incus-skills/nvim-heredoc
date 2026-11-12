# nvim-heredoc

Reliable shell heredoc editing support for Neovim.

The initial integration target is LazyVim, but the editing logic should remain usable independently of a particular Neovim distribution.

## Project objective

Provide predictable editing support for shell `<<-` (tab-stripping) heredocs:

- Insert a matching closing delimiter automatically.
- Keep the opener, body, and closing delimiter structurally indented rather than forcing them to column zero.
- Preserve relative indentation when text is pasted into the body.
- Avoid changing ordinary `<<` heredocs.
- Work in Bash, POSIX `sh`, and Zsh buffers.
- Coexist with the user's existing completion, pair, indentation, and formatting configuration.

## Semantics that constrain the implementation

A shell `<<-` heredoc removes leading **tab characters** from body lines and from the terminating delimiter. It does not remove leading spaces. This is shell behaviour, not an editor preference.

Consequently, the implementation must distinguish structural tabs from body content and must not silently strip or rewrite pasted whitespace. Tabs that are part of the payload are also subject to the shell's `<<-` tab-stripping rule; tests must make this visible.

Ordinary `<<` heredocs are outside the managed scope and must remain untouched.

## Current status

Repository initialisation and design/validation work are in progress. No installer should be treated as validated until both buffer-level and shell-delivery tests pass.

See [the design contract](docs/design.md) and [the initial implementation task](tasks/active/001-core-design-and-prototype.md).
