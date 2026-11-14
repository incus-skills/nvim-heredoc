# Scanner interface and prototype boundaries

Module: `nvim-heredoc.scanner`

Entry point:

```lua
local scanner = require("nvim-heredoc.scanner")
local result = scanner.scan(source_text)
```

The scanner is buffer-independent and does not mutate its input. It normalises CRLF/CR line endings for line analysis and returns:

- `complete`: whether the source was scanned without a lexical ambiguity or unresolved heredoc;
- `regions`: managed `<<-` heredoc regions only;
- `diagnostics`: line-associated reasons why the scan is incomplete or uncertain.

A completed region currently contains:

| Field | Meaning |
|---|---|
| `operator` | Always `<<-` for a returned managed region |
| `opener_line` | 1-based physical line containing the operator |
| `command_end_line` | Last physical line of the logical command |
| `queue_position` | Heredoc declaration order on that command |
| `delimiter_original` | Delimiter spelling as written, including quotes/escapes |
| `delimiter` | Quote-removed delimiter used for terminator matching |
| `delimiter_quoted` | Whether quoting/escaping suppresses body expansion |
| `body_start_line` | First physical body line |
| `body_end_line` | Physical line immediately before the terminator |
| `terminator_line` | 1-based terminator line |
| `opener_prefix` | Original leading whitespace bytes before the opener command; never rewritten by the editor |
| `structural_prefix` | Literal TAB bytes representing the opener's visual indentation column; used for the closing delimiter |
| `body_prefix` | `structural_prefix` plus one additional literal TAB; used for every body line |
| `structural_column` | Visual column occupied by the opener's original leading whitespace |
| `tabstop` | Buffer tabstop used to calculate visual columns |
| `structural_tabs_only` | Whether that visual column can be represented exactly by a TAB-only prefix |
| `confidence` | `lexical`, `unsupported-indent`, `uncertain`, or `incomplete` |
| `editable` | Whether this prototype considers the region safe for an editing operation |

An unterminated managed heredoc is returned with `confidence = "incomplete"`, no body end/terminator line, and `editable = false`. Its opener may still be marked safe for closer insertion when its visual indentation column can be represented exactly by a TAB-only prefix. If lexical state becomes ambiguous, scanning stops rather than treating possible heredoc payload as subsequent shell source. Any uncertainty disables editing for all regions returned by that scan.

## Current supported lexical subset

- Operators outside single/double quotes, escaped text, and comments.
- Distinguishing `<<-`, ordinary `<<`, and `<<<`.
- Quoted and escaped delimiter words, preserving both source spelling and quote-removed match value, including valid empty quoted delimiters.
- Multiple heredocs on one logical command, consumed in declaration order.
- Backslash-newline command continuations.
- `<<-` terminator matching after stripping leading TAB bytes.
- Basic arithmetic-command and `[[ ... ]]` contexts to avoid treating shift/comparison operators as heredocs.
- A bounded subset of `$(...)` command substitutions and nested substitutions, sufficient to skip ordinary substitutions that contain no heredoc redirection.
- Arithmetic expansions inside supported command-substitution contexts.

## Independent parser oracle

The CI core job uses the mvdan/sh parser through the `shfmt --to-json` interface to establish that selected unsupported-grammar fixtures are valid Bash programs. The Lua scanner is then required to report uncertainty for those same fixtures and must not mark any returned region editable. This deliberately separates *syntactic validity* from *safe editability*: mvdan/sh is a test oracle, not a runtime dependency or an authority that can override the Lua scanner's conservative gate. The fixtures currently cover backtick substitution and a heredoc nested inside command substitution.

## Explicit limits

This is not a full parser for Bash, POSIX sh, or Zsh. Backtick substitutions, heredoc redirections inside command substitutions, multiline quoted commands, and other unsupported lexical contexts produce an uncertainty diagnostic. The scan stops at that point and no returned region is editable. The scanner's subset has not yet been demonstrated equivalent across every shell grammar edge case; new syntax should be added only with regression coverage for all intended dialects.

## Editing integration status

The repository now contains an initial Neovim buffer integration in `nvim-heredoc.init`, plus pure helpers in `nvim-heredoc.editing`.

The current integration:

- attaches to Bash, `sh`, and Zsh buffers;
- inserts a closer for a safely recognised incomplete managed heredoc;
- derives the closer from the opener-aligned structural TAB prefix;
- gives body lines a separate prefix with one additional literal TAB;
- tracks changed line ranges with `nvim_buf_attach(on_lines)`;
- retains disjoint notifications as separate ranges, rebases earlier pending ranges when edits insert/delete lines, and merges only overlapping or adjacent ranges;
- prefixes only changed lines that intersect a scanner-confirmed body range;
- avoids duplicating an already-present body prefix.

The integration is headlessly tested, but this does not establish compatibility with LazyVim, `mini.pairs`, `blink.cmp`, or `conform.nvim`. Plugin-specific controls remain deliberately untouched pending inspection of the actual installed revisions and configuration.

These behaviours remain prototype-level. The `editable` field is a conservative gate for the current editing operations, not proof that every possible shell construct has been parsed. Headless regressions cover disjoint edits; insertion/deletion before earlier pending edits; an overlapping replacement with a line-count change; a replacement spanning multiple disjoint pending ranges; and insertion at a pending-range boundary. They assert that changed content is prefixed while untouched neighboring lines remain byte-for-byte unchanged. Partial notifications, arbitrary concurrent buffer mutation paths, and broader real-workstation validation remain open.
