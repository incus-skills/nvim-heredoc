# Design contract

## 1. Scope

The managed construct is a shell `<<-` heredoc. The implementation must not manage ordinary `<<` heredocs or here-strings (`<<<`).

Initial filetypes: Bash, POSIX `sh`, and Zsh. The same lexical core should serve all three; Treesitter may be an optional aid but must not be a runtime requirement.

## 2. Shell semantics

For `<<-`:

- The shell strips leading TAB bytes from each body line.
- The shell strips leading TAB bytes when matching the terminating delimiter.
- Leading spaces are not stripped.
- Multiple heredocs on one command are consumed in declaration order.
- Quoted delimiters suppress parameter, command, and arithmetic expansion in the body; delimiter quoting must be resolved for matching without changing the source text.
- The body begins after the complete command line (including any continued command lines) and heredoc bodies are consumed in queue order.

These rules need explicit regression tests. The editor must not claim to preserve payload tabs that the shell itself strips.

## 3. Editing behaviour

- Recognise only valid `<<-` operators outside shell quotes and comments.
- Ignore `<<<` and ordinary `<<`.
- Track multiple pending heredocs in declaration order.
- Recognise delimiter lines according to shell tab-stripping semantics.
- Insert a matching closer automatically without placing it at hard column zero when the opener has structural indentation.
- Preserve all existing body whitespace when indenting or pasting. Never implement paste handling by removing all leading whitespace and prefixing a replacement.
- Any structural prefix added to a body line must be a TAB byte if the resulting script is expected to rely on `<<-` tab stripping.
- If the opener's indentation uses spaces in a way that cannot be represented as tabs without changing alignment, do not silently rewrite it. Report or document the limitation and leave the source intact.
- Keep ordinary `<<` heredocs byte-for-byte unaffected by managed editing actions.

## 4. Plugin coexistence

The implementation must be based on verified APIs from the installed versions of plugins, not guessed buffer variables or configuration flags.

Inspect and test the actual installed implementations/configuration before changing behaviour for:

- `mini.pairs`
- `blink.cmp`
- LazyVim indentation and completion
- `conform.nvim`

Do not globally disable completion. If literal heredoc regions need different completion/pair behaviour, scope that behaviour to the detected managed region and preserve a path for future embedded-language support.

Use `shfmt` for Bash and POSIX `sh` only. Do not configure `shfmt` as the Zsh formatter.

## 5. Scanner architecture

Use a shared lexical scanner rather than requiring Treesitter. It must account for:

- Single-quoted, double-quoted, and escaped text when detecting operators.
- Comments, without treating `#` inside words/quotes as a comment.
- Here-strings versus heredoc operators.
- Quoted and escaped delimiters.
- Command continuations and the point at which pending heredoc bodies begin.
- Multiple heredocs attached to one command.
- Nested shell constructs sufficiently to avoid false operator detection.

The scanner should expose region information (opener, body, delimiter, queue position, and confidence/ambiguity) to editing integrations. Ambiguous or malformed input should fail conservatively: do not mutate unrelated text.

## 6. Validation contract

Validation has two independent layers.

### Buffer-level tests

Verify exact bytes and cursor placement for:

- A single indented `<<-` heredoc.
- An opener inside an indented function/conditional.
- Multiple heredocs on one command.
- Quoted and escaped delimiters.
- Empty body lines.
- Nested shell constructs and command continuations.
- Pasting lines with mixed spaces and tabs, preserving relative indentation.
- Existing delimiter lines.
- Ordinary `<<` and `<<<` remaining untouched.
- Malformed/incomplete openers failing conservatively.

### Shell-delivery tests

Run generated scripts through the relevant shells and compare captured payload bytes. Include:

- Leading spaces.
- Leading tabs (demonstrating that `<<-` strips them).
- Relative indentation.
- Multiple heredocs.
- Quoted delimiter expansion behaviour.
- Delimiter matching with leading tabs.
- Bash, a POSIX shell, and Zsh where available.

A visually correct buffer is not sufficient evidence that the shell receives the intended payload.

## 7. Delivery

The first deliverable should be a tested core and a minimal LazyVim integration, followed by an installer only after the behaviour and plugin APIs are validated. Installation must back up replaced files and be repeatable. Tests should run independently of a user's full LazyVim configuration wherever possible.
