# Scanner interface and prototype boundaries

Module: \`nvim-heredoc.scanner\`

Entry point:

\`\`\`lua
local scanner = require("nvim-heredoc.scanner")
local result = scanner.scan(source_text)
\`\`\`

The scanner is buffer-independent and does not mutate its input. It normalises CRLF/CR line endings for line analysis and returns:

- \`complete\`: whether the source was scanned without a lexical ambiguity or unresolved heredoc;
- \`regions\`: managed \`<<-\` heredoc regions only;
- \`diagnostics\`: line-associated reasons why the scan is incomplete or uncertain.

A completed region currently contains:

| Field | Meaning |
|---|---|
| \`operator\` | Always \`<<-\` for a returned managed region |
| \`opener_line\` | 1-based physical line containing the operator |
| \`command_end_line\` | Last physical line of the logical command |
| \`queue_position\` | Heredoc declaration order on that command |
| \`delimiter_original\` | Delimiter spelling as written, including quotes/escapes |
| \`delimiter\` | Quote-removed delimiter used for terminator matching |
| \`delimiter_quoted\` | Whether quoting/escaping suppresses body expansion |
| \`body_start_line\` | First physical body line |
| \`body_end_line\` | Physical line immediately before the terminator |
| \`terminator_line\` | 1-based terminator line |
| \`structural_prefix\` | Leading whitespace bytes before the opener command |
| \`structural_tabs_only\` | Whether that prefix contains only TAB bytes |
| \`confidence\` | \`lexical\`, \`unsupported-indent\`, \`uncertain\`, or \`incomplete\` |
| \`editable\` | Whether this prototype considers the region safe for an editing operation |

An unterminated managed heredoc is returned with \`confidence = "incomplete"\`, no body end/terminator line, and \`editable = false\`. If lexical state becomes ambiguous, scanning stops rather than treating possible heredoc payload as subsequent shell source. Any uncertainty disables editing for all regions returned by that scan.

Ordinary \`<<\` heredocs are not returned, but their delimiter/body are consumed so the body is not scanned as shell source. Here-strings (\`<<<\`) are ignored.

## Current supported lexical subset

- Operators outside single/double quotes, escaped text, and comments.
- Distinguishing \`<<-\`, ordinary \`<<\`, and \`<<<\`.
- Quoted and escaped delimiter words, preserving both source spelling and quote-removed match value, including valid empty quoted delimiters.
- Multiple heredocs on one logical command, consumed in declaration order.
- Backslash-newline command continuations.
- \`<<-\` terminator matching after stripping leading TAB bytes.
- Basic arithmetic-command and \`[[ ... ]]\` contexts to avoid treating shift/comparison operators as heredocs.

## Explicit limits

This is not a full parser for Bash, POSIX sh, or Zsh. In this prototype, command substitutions (\`$(...)\`), backtick substitutions, multiline quoted commands, and other unsupported lexical contexts produce an uncertainty diagnostic. The scan stops at that point and no returned region is editable. More syntax may be supported only when the behaviour is covered by regression cases for all intended shell dialects.

The scanner's \`editable\` field is a conservative gate for future integrations, not proof that every possible shell construct has been parsed. Neovim buffer editing, automatic closer insertion, paste handling, and plugin integration are not implemented by this module yet.
