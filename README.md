# nvim-heredoc

Reliable shell heredoc editing support for Neovim.

The initial integration target is LazyVim, but the editing logic should remain usable independently of a particular Neovim distribution.

## Project objective

Provide predictable editing support for shell heredocs, with managed body formatting limited to `<<-` (tab-stripping) heredocs:

- Insert a matching closing delimiter automatically for managed `<<-` openers.
- Keep managed openers and closing delimiters structurally indented within surrounding shell code.
- Preserve relative indentation and existing bytes when multiline content is pasted.
- Recognise matching closers for either `<<` or `<<-` despite leading spaces or TABs; normalise closers created or actively maintained by the plugin.
- Keep ordinary `<<` heredoc bodies outside managed formatting, and leave here-strings (`<<<`) untouched.
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

Ordinary `<<` heredocs are outside the managed body-formatting scope. Their matching closer may be recognised despite leading spaces or TABs, but existing terminator lines are not rewritten by generic buffer processing. The body is never adopted or reformatted. Here-strings (`<<<`) remain entirely outside scope.

For either operator, leading spaces or TABs may be ignored when recovering the delimiter identity; trailing whitespace is not ignored, and the delimiter itself must still match exactly. This editor-side recognition tolerance does not change native shell syntax. Closer normalisation is limited to lines the plugin creates or is actively maintaining as part of an owned editing operation. Automatically fixing pre-existing indented terminators is a separate, deferred opt-in feature.

## Architecture

**The interactive editing contract is Return-local, not document-global.** The plugin acts when the user presses Return after completing a managed <<- opener. That event commits to the new heredoc: the plugin inserts the matching closer immediately, placing it within the available enclosing shell structure (for example, before an existing function-closing brace). The inserted closer establishes the end of this heredoc's lexical input scope. Body text between the opener and closer is payload, even when it resembles another shell heredoc opener. The plugin does not need a document-wide ledger of other heredocs, opener identities, or competing future terminators to establish this scope.

The lexical scanner remains a bounded helper for recognising the current opener, delimiter, mode, and safe local boundaries. It is not a mandate to reconstruct the entire document's heredoc ownership or shell structure. Existing shell indentation machinery remains responsible for ordinary function and compound-command indentation wherever it can provide that context. Do not duplicate it with a general structural parser merely to place this local closer.

An established heredoc body is also a lexical zone for syntax representation: the containing shell parser must not claim embedded payload constructs (including an inner heredoc `EOF`) as active syntax of the outer shell document. The scanner-established body boundary is authoritative for both editing and future syntax presentation. The current Tree-sitter Bash interpretation of an inner `EOF` as an outer-shell construct is a known mismatch with this policy. How payloads are eventually represented—contained-language parsing/injection or opaque content—remains future work; deferring that choice does not defer the boundary requirement.

Typing the opener alone does not commit a closer; Return does. Existing-buffer recovery and other editing paths must not silently turn this into a general opener-time or document-wide tracking system.

Paste handling must operate on the complete changed range and preserve existing bytes. If the range or region is ambiguous, the safe behaviour is to leave the text unchanged.

Formatting is separate from interactive editing. `shfmt` is for Bash and POSIX `sh` only, not Zsh. Its effect on heredoc payload bytes must be tested rather than assumed.

## Future development context

The adopted lexical-zone policy and remaining embedded-payload design questions are recorded in [future development context](docs/future-development-context.md). The current syntax-presentation mismatch and its bounded implementation work are tracked in [deferred syntax-presentation investigation](tasks/deferred/002-syntax-presentation-lexical-zone-containment.md). Language identification, diagnostics/completion, and formatter isolation remain separate future integrations.

## Review process and reusable skills

Project reviews also develop reusable review capabilities. The [review process](docs/review-process.md) describes how architectural reassessment, necessity/evidence analysis, critique of review criteria, and reconstructability are considered without turning them into a fixed rubric.

Emerging capabilities are collected as provisional candidates in [the review-skills space](skills/review/README.md). Each review cycle can draw on, challenge, and refine that collection; applying a candidate in another project is a further test of its transferability.

## Project status: pre-release field validation

The core heredoc editing and autoformatting objective has, in large part, been achieved. The implementation now provides automatic closer insertion, structural indentation, payload/paste preservation, and tested coexistence with the pinned LazyVim integration environment. The five-layer CI workflow covers the scanner, Neovim buffer integration, shell delivery, formatter behaviour, and LazyVim/plugin coexistence.

The project is therefore moving from core implementation toward a **pre-release for field testing**. The pre-release should provide a stable, identifiable baseline that can be exercised in real LazyVim configurations. Field use should help expose remaining functional edge cases, runtime-specific behaviour, efficiency issues, and opportunities to simplify the implementation. Those findings should be evaluated against the original editing objective rather than treated as a mandate to expand the feature set.

This is not a claim that every environment or heredoc form is already covered. In particular, [Task 001](tasks/active/001-core-design-and-prototype.md) retains the remaining verification and simplification work. Hosted CI evidence and live workstation/field observations must be reported separately.

### Stretch goals

Nested heredoc indentation and embedded-language presentation (including possible Tree-sitter injection) are stretch goals beyond the core pre-release objective. They explore editor behaviour that extends the native Bash heredoc metaphor: Bash does not maintain nested indentation levels for successive `<<-` processing, and embedded-language presentation introduces a separate interpretation of payload regions.

These investigations must not block the pre-release or be presented as missing prerequisites for the core autoformatting objective. Keep them separately scoped until field testing of the core behaviour provides a reason to prioritise them.

The adopted lexical-zone boundary and the exploratory syntax-presentation work are recorded in [future development context](docs/future-development-context.md); the deferred syntax-presentation investigation is tracked in [Task 002](tasks/deferred/002-syntax-presentation-lexical-zone-containment.md).

