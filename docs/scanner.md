# Scanner interface and prototype boundaries

Module: `nvim-heredoc.scanner`

Entry point:

```lua
local scanner = require("nvim-heredoc.scanner")
local result = scanner.scan(source_text)
```

The scanner also exposes a deliberately narrower `parse_openers(source, opts)` helper for the Return transition. It parses only the completed command text supplied by the caller and returns opener records with delimiter and structural-prefix information. It does not scan for terminators or inspect surrounding buffer lines. The Return integration currently accepts exactly one managed `<<-` opener through this path; multiple queued heredocs remain conservative until their distinct body/terminator placement is implemented.

The scanner is buffer-independent and does not mutate its input. It normalises CRLF/CR line endings for line analysis and returns:

- `complete`: whether the source was scanned without a lexical ambiguity or unresolved heredoc;
- `regions`: managed `<<-` heredoc regions only;
- `heredocs`: all recognised heredoc regions, including ordinary `<<`, used to detect operator transitions;
- `diagnostics`: line-associated reasons why the scan is incomplete or uncertain;
- `checkpoints`: completed heredoc command-group boundaries, as described below.

A completed region currently contains:

| Field | Meaning |
|---|---|
| `operator` | Always `<<-` for a returned managed region |
| `opener_line` | 1-based physical line containing the operator |
| `command_start_line` | First physical line of the logical command |
| `command_end_line` | Last physical line of the logical command; also the generation-local command-group key |
| `queue_position` | Heredoc declaration order on that command |
| `is_final_in_queue` | Whether this is the final heredoc declaration in the command queue |
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

## Command-group checkpoint observations

**Status: current scanner observations.** These fields are additive observations of the scanner's existing queue-consumption process. They do not change shell recognition, document-level completeness, or editing authority.

### Region observations

Each recognised heredoc region includes:

| Field | Meaning |
|---|---|
| `command_start_line` | 1-based physical line at which the logical command begins. All regions from that command share the value. |
| `is_final_in_queue` | True only for the final heredoc declaration in that command's queue. |

The existing `command_end_line` value serves as the command group's generation-local `group_key`. All regions in the same command group therefore share that key. It is a coordinate-derived association, not a persistent command identity.

### Checkpoint observations

The scan result includes a `checkpoints` collection. Each checkpoint records:

- `pos`: the 1-based boundary position immediately after the final heredoc terminator;
- `group_key`: the command-group key shared by that group's region records.

A checkpoint is emitted only after the entire heredoc queue has been consumed and the scanner index has advanced to the following line position. A terminator found for an earlier queue member is not a checkpoint while later members remain pending. A command group with no heredoc queue does not produce a checkpoint.

All observation coordinates use scanner-local, 1-based line positions. The incremental merge consumer translates region coordinates, group keys, and checkpoint positions into full-buffer coordinates using the bounded attempt's starting offset.

### Relationship to conservative downgrade

The scanner's existing policy of downgrading all regions when `complete = false` remains authoritative for consumers that do not perform merge-level salvage. Checkpoint observations do not change the document-level `complete` flag or that downgrade policy.

The merge consumer, not the scanner, decides how observations affect preservation and salvage. These records report only which command groups the scanner actually completed; they do not themselves make a partial document snapshot trusted.

## Current supported lexical subset

- Operators outside single/double quotes, escaped text, and comments.
- Distinguishing `<<-`, ordinary `<<`, and `<<<`.
- Quoted and escaped delimiter words, preserving both source spelling and quote-removed match value, including valid empty quoted delimiters.
- Multiple heredocs on one logical command, consumed in declaration order.
- Backslash-newline command continuations.
- Terminator recovery for both `<<` and `<<-`: compare the candidate delimiter after ignoring leading spaces and TABs, while retaining exact delimiter identity and not ignoring trailing whitespace. This is an editor recovery rule, not native shell parsing semantics.
- Basic arithmetic-command and `[[ ... ]]` contexts to avoid treating shift/comparison operators as heredocs.
- A bounded subset of `$(...)` command substitutions and nested substitutions, sufficient to skip ordinary substitutions that contain no heredoc redirection.
- Arithmetic expansions inside supported command-substitution contexts.

## Independent parser oracle

The CI core job uses the mvdan/sh parser through the `shfmt --to-json` interface to establish that selected unsupported-grammar fixtures are valid Bash programs. The Lua scanner is then required to report uncertainty for those same fixtures and must not mark any returned region editable. This deliberately separates *syntactic validity* from *safe editability*: mvdan/sh is a test oracle, not a runtime dependency or an authority that can override the Lua scanner's conservative gate. The fixtures currently cover backtick substitution and a heredoc nested inside command substitution.

## Explicit limits

This is not a full parser for Bash, POSIX sh, or Zsh. Backtick substitutions, heredoc redirections inside command substitutions, multiline quoted commands, and other unsupported lexical contexts produce an uncertainty diagnostic. The scan stops at that point and no returned region is editable. The scanner's subset has not yet been demonstrated equivalent across every shell grammar edge case; new syntax should be added only with regression coverage for all intended dialects.

## Governing editing contract

The scanner is a bounded lexical helper. Its result fields describe what the current scanner can recognise; they do not define a requirement to maintain document-wide heredoc ownership or a graph of opener identities.

The interactive editing commitment occurs on **Return after a completed managed opener**:

- Typing the opener does not itself create a persistent editing obligation.
- Return recognises the completed <<- opener and its delimiter.
- The plugin immediately inserts the matching closer at the local structural position.
- That inserted closer bounds the new heredoc body. Text between opener and closer is payload, including lines that resemble other heredoc openers.
- Other heredocs elsewhere in the document are irrelevant to establishing this scope.

The scanner may still recognise ordinary heredoc bodies so their payload is not misread as shell syntax in the supported lexical subset. It may also retain declaration-order handling for multiple heredocs on one command as a shell-language fact. Neither capability authorises a general document-wide tracking architecture for the Return-local path.


## Lexical-zone boundary for syntax consumers

The scanner's completed heredoc records expose `body_start_line`, `body_end_line`, and `terminator_line`. These are the scanner-derived line boundaries for consumers that need to reason about payload regions. The `heredocs` collection includes ordinary `<<` and managed `<<-` records; `regions` remains the managed `<<-` subset used for body formatting.

### Closer recovery is separate from body adoption

Both operators use the same editor-side recognition tolerance for an intended matching closer: leading spaces and TABs may be ignored when identifying the delimiter, but trailing whitespace is not ignored and the delimiter spelling must match exactly. Recognition is separate from editing authority: a pre-existing terminator is left byte-for-byte unchanged by generic buffer processing. When the plugin creates or actively maintains a closer as part of an owned operation, it uses the operator-appropriate form:

- `<<`: remove all leading indentation; the closer is left-justified.
- `<<-`: use the opener's `structural_prefix`, represented by literal TAB bytes.

This is an editor recovery rule, not a claim that the indented candidate is valid shell syntax. Native shell semantics remain distinct: ordinary `<<` requires a left-justified terminator, while `<<-` strips leading TABs but not spaces.

The distinction does not expand body adoption. Ordinary `<<` records remain in `heredocs` only; they are not added to `regions`, and their payload bytes are never passed through managed body-prefix formatting. Recognition of an ordinary `<<` closer does not authorise generic buffer processing to rewrite it. Pre-existing closer normalisation is deferred to a separate opt-in operation. Here-strings (`<<<`) remain outside both recognition and editing scope.

A missing or non-matching delimiter remains incomplete. Recognition must not consume a delimiter-like body line with a different spelling, nor should trailing whitespace be silently trimmed to manufacture a match.

The adopted project policy requires future syntax-presentation consumers to respect these established boundaries. They must not infer a competing payload boundary from Tree-sitter Bash nodes or delimiter-looking text inside a body. This scanner interface is line-based and currently recomputes from source; it does not yet provide a Tree-sitter included-range adapter, incremental region lifecycle, or payload-language classification. Those are implementation questions tracked in [Task 002](../tasks/active/002-syntax-presentation-lexical-zone-containment.md).

This does not make Tree-sitter a dependency for scanning or editing. The scanner remains the structural source of truth, and unknown payloads must not be silently parsed as Bash.

## Editing integration status

The current production integration has evolved through several approaches, including retained scan snapshots, transition reconciliation, and Return-local insertion. Those mechanisms are implementation history, not all architectural requirements. The governing question for future changes is whether a mechanism is strictly necessary to fulfil the Return-local bounded-scope contract.

The intended interactive behaviour is:

- recognise the completed managed opener at Return;
- insert its matching closer immediately, before an existing enclosing structural closer where appropriate;
- apply the body prefix and preserve the Insert-mode cursor position;
- keep subsequent body edits and paste operations within the established lexical scope;
- avoid duplicate edits when Neovim delivers the Return transition through multiple callbacks;
- leave the buffer unchanged when the local opener or placement is ambiguous.

The integration is headlessly tested, but hosted tests do not establish compatibility with every user's live configuration or event ordering. Do not describe the behaviour as solved in a user's workstation until verified there. When debugging, reproduce the actual Return transition and instrument the development checkout or an isolated worktree; do not ask the user to edit an installed plugin copy as a substitute for a controlled diagnostic change.

The scanner's complete, regions, heredocs, and diagnostics fields remain useful implementation/test interfaces for the current code. They must not be mistaken for a project-level requirement to preserve global scan history, cross-document opener identity, or source-order recovery machinery.
