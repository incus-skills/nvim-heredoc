# Design contract

## 1. Scope

The managed construct is a shell `<<-` heredoc. The implementation must not manage ordinary `<<` heredocs or here-strings (`<<<`).

Initial filetypes: Bash, POSIX `sh`, and Zsh. The same lexical core serves all three. Treesitter parsers may be available and may provide optional structural assistance, but parser availability and parse success are not runtime requirements for heredoc recognition or editing.

## 2. Shell semantics and the indentation model

For `<<-`:

- The shell strips leading TAB bytes from each body line.
- The shell strips leading TAB bytes when matching the terminating delimiter.
- Leading spaces are not stripped.
- Multiple heredocs on one command are consumed in declaration order.
- Quoted delimiters suppress parameter, command, and arithmetic expansion in the body; delimiter quoting must be resolved for matching without changing the source text.
- The body begins after the complete command line (including any continued command lines), and heredoc bodies are consumed in queue order.

The editor must distinguish two different kinds of indentation:

1. **Structural indentation** places the opener and terminator within the surrounding shell construct. For a managed `<<-` heredoc, structural indentation is represented by leading TAB bytes so the shell can remove it.
2. **Content indentation** belongs to the payload. Leading spaces are preserved. Leading TAB bytes are subject to the shell's `<<-` stripping rule and therefore cannot be promised as payload indentation.

The displayed width of a structural TAB is determined by the buffer's `tabstop`; it is not a conversion to spaces. The opener may retain leading spaces when its visual indentation column is exactly representable by leading TABs at that tabstop. In that case, the editor leaves the opener bytes unchanged and derives an equivalent TAB prefix for body lines and the terminator. For example, with `tabstop=2`, an opener indented by two spaces is visually aligned with a body/terminator prefix of one literal TAB. If the opener's visual column cannot be represented exactly by leading TABs (for example, three spaces at `tabstop=2`), the region remains non-editable rather than being silently shifted. A visually nested example must not be interpreted as evidence that literal leading spaces on a terminator are valid.

For example, the structural TABs below are literal TAB bytes; the spaces inside the body are payload:

```sh
some_function() {
	if some_condition; then
		cat <<-'EOF'
		This content remains indented.
		Pasted content retains its indentation.

		Nested-looking content:
		  level two
		  level two
		EOF
	fi
}
```

The shell removes the structural TAB prefix from each body line and the terminator. The two spaces before each `level two` line remain in the payload.

These rules need explicit regression tests. The editor must not claim to preserve payload tabs that the shell itself strips.

## 3. Shared region model

Recognition is the common authority for all editing integrations. Indentation, paste handling, automatic closer insertion, auto-pairs, completion, and formatting integration must consume the same region information; they must not independently guess the active heredoc by searching for the nearest preceding opener.

The scanner should expose a buffer-independent result with, at minimum:

- opener line and source span;
- operator kind (`<<-`, ordinary `<<`, or `<<<`);
- original delimiter spelling and quote-removed delimiter value;
- whether delimiter quoting suppresses expansion;
- command boundary at which heredoc body consumption begins;
- queue position for multiple heredocs on the same command;
- body start and end lines, when known;
- terminator line and matched delimiter, when present;
- structural indentation prefix and its byte representation;
- confidence/ambiguity status and a reason when the region cannot safely be resolved.

The scanner processes shell source in lexical order. It recognises pending heredocs on a command, waits until that command's complete logical line ends, then consumes bodies in declaration order. A completed earlier heredoc must not be mistaken for the active region when later nested shell constructs contain another opener.

The scanner is conservative, not a claim to implement every shell grammar production. On malformed or ambiguous input it must report uncertainty and avoid authorising destructive edits.

## 4. Editing behaviour

- Recognise only valid `<<-` operators outside shell quotes and comments.
- Ignore `<<<` and ordinary `<<` for managed editing.
- Track multiple pending heredocs on a command in declaration order.
- Recognise delimiter lines according to shell tab-stripping semantics.
- Insert a matching closer automatically without placing it at hard column zero when the opener has structural TAB indentation.
- The closer uses a leading-TAB prefix that occupies the same visual column as the opener. The opener's original indentation bytes are not rewritten; a space-indented opener is supported only when its visual column is exactly representable by TABs at the buffer's tabstop. Leading spaces are not a valid substitute for TABs on the closer.
- Preserve all existing body whitespace when indenting or pasting. Never implement paste handling by removing all leading whitespace and prefixing a replacement.
- Any structural prefix added to a body line must be a TAB byte if the resulting script is expected to rely on `<<-` tab stripping.
- If the opener's indentation uses spaces in a way that cannot be represented by structural tabs without changing alignment, do not silently rewrite it. Report or document the limitation and leave the source intact.
- Keep ordinary `<<` heredocs byte-for-byte unaffected by managed editing actions.

## 5. Interactive editing and paste preservation

Interactive editing is region-based rather than a sequence of isolated current-line corrections.

- Automatic closer insertion is driven by a recognised opener and the shared region model, not by the first blank line encountered after an opener.
- Paste handling must identify the complete changed range. It must not assume that a `TextChangedI` event describes only the cursor's current line.
- The paste operation must preserve the relative indentation of the inserted lines. It must not trim leading whitespace from each line.
- Structural indentation may be added only when the edit context establishes that the prefix is not already present. Repeated events must not duplicate prefixes.
- Empty lines, lines containing only spaces, and lines containing tabs require explicit handling and tests.
- If the changed range cannot be reliably identified, or the region is ambiguous, leave the inserted text unchanged rather than guessing.
- Neovim's normal indentation, pair insertion, and completion behaviour should be allowed to coexist unless a verified, region-scoped integration is necessary.

The initial Neovim integration runs on `InsertLeave` and `TextChanged`, uses the shared scanner, inserts a closer for a safe incomplete opener, and applies idempotent structural TAB prefixes to the recognised body range. It now tracks changed line ranges with `nvim_buf_attach(on_lines)` and prefixes only the intersection of a changed range and a recognised heredoc body. `InsertLeave` performs a full-region pass and inserts a closer for a safe incomplete opener. Headless tests verify range isolation and cursor preservation. This is still an initial integration prototype: extmark behaviour, plugin coexistence, and more complex edit sequences remain to be validated. A future implementation may use extmarks or another stable range-tracking mechanism, but the design contract does not prescribe a specific Neovim API until the prototype demonstrates the required behaviour.

## 6. Plugin coexistence and formatting

The implementation must be based on verified APIs from the installed versions of plugins, not guessed buffer variables or configuration flags.

Inspect and test the actual installed implementations/configuration before changing behaviour for:

- `mini.pairs`
- `blink.cmp`
- LazyVim indentation and completion
- `conform.nvim`

Do not globally disable completion. If literal heredoc regions need different completion/pair behaviour, scope that behaviour to the detected managed region and preserve a path for future embedded-language support.

Use `shfmt` for Bash and POSIX `sh` only. Do not configure `shfmt` as the Zsh formatter.

Save-time formatting is a separate mechanism from interactive indentation. Tests must establish that the configured `shfmt -i 0 -p` invocation preserves heredoc payload bytes and does not invalidate the scanner's region model. Do not assume this merely because the formatter is appropriate for the surrounding shell language. Zsh formatting remains unassigned until a suitable formatter is selected.

## 7. Scanner architecture and grammar limits

Use a shared lexical scanner rather than requiring Treesitter. It must account for:

- Single-quoted, double-quoted, and escaped text when detecting operators.
- Comments, without treating `#` inside words/quotes as a comment.
- Here-strings versus heredoc operators.
- Quoted and escaped delimiters.
- Command continuations and the point at which pending heredoc bodies begin.
- Multiple heredocs attached to one command.
- Nested shell constructs sufficiently to avoid false operator detection.

The scanner should expose region information to editing integrations. It must explicitly record unsupported or ambiguous grammar cases. It must not report a high-confidence region merely because a line resembles a heredoc opener.

Treesitter may be used as an optional cross-check or structural aid when a parser is available and successfully parses the relevant buffer. The lexical scanner remains authoritative for shared behaviour and must work when Treesitter is absent, unavailable for a filetype, or unable to parse an incomplete editing buffer.

The first implementation in `lua/nvim-heredoc/scanner.lua` is a deliberately bounded lexical prototype. It handles simple command lines, line continuations, comments, quotes, escaped operators, ordinary heredoc body skipping, declaration-order queues, arithmetic expansions, and ordinary command substitutions without nested heredocs. A heredoc redirection inside command substitution, backtick substitution, multiline quoted commands, and other unsupported contexts remain uncertain and must not be edited. It does not claim complete shell grammar coverage. The supported subset and diagnostics must expand only alongside regression tests.

## 8. Validation contract

Validation has independent layers.

### Buffer-level tests

Verify exact bytes, region results, and cursor placement for:

- A single indented `<<-` heredoc.
- An opener inside an indented function/conditional.
- Multiple heredocs on one command.
- Quoted and escaped delimiters.
- Empty body lines and whitespace-only lines.
- Nested shell constructs and command continuations.
- Pasting multiple lines with mixed spaces and tabs, preserving relative indentation.
- Paste events/ranges that are repeated, partial, or ambiguous.
- Existing delimiter lines.
- Ordinary `<<` and `<<<` remaining untouched.
- Malformed/incomplete openers failing conservatively.
- Structural TAB indentation versus space-indented openers and terminators.

### Shell-delivery tests

Run generated scripts through the relevant shells and compare captured payload bytes. Include:

- Leading spaces.
- Leading tabs (demonstrating that `<<-` strips them).
- Relative indentation.
- Multiple heredocs.
- Quoted delimiter expansion behaviour.
- Delimiter matching with leading tabs and rejection of leading spaces.
- Bash, a POSIX shell, and Zsh where available.

### Formatter tests

Run the configured `shfmt -i 0 -p` command on representative Bash and POSIX `sh` fixtures. Compare payload bytes before and after formatting, and verify opener/body/terminator structure. Confirm that Zsh is not assigned to `shfmt`.

A visually correct buffer is not sufficient evidence that the shell receives the intended payload.

## 9. Delivery

The canonical implementation is the tested Lua source in the repository. The initial workstation delivery mechanism is the repository provisioning script, not a plugin-manager installation route. The provisioner copies the same Lua modules used by the test suite and generates thin per-filetype entrypoints; it does not embed a second implementation.

The provisioner owns exactly six outputs: the three modules under `lua/nvim-heredoc/` and the three generated files under `after/ftplugin/{bash,sh,zsh}.lua`. Re-running it replaces those declared outputs and leaves unrelated configuration untouched. The previous three ftplugins were themselves provisioned outputs, so preserving or backing them up is not part of this replacement contract. This ownership rule would not justify overwriting independently maintained user files.

The provisioner is repeatable and accepts an explicit `NVIM_CONFIG_DIR` for isolated testing or a non-default configuration tree. Its installer test verifies copied module bytes, generated entrypoint contents, and repeat-execution stability. The provisioner requires the project's adopted content-emission convention, including function-wrapped content and Markdown terminal reporting through `glow`.

The provisioned entrypoints call `require("nvim-heredoc").setup_buffer()`; they do not require a plugin runtime entrypoint, plugin-manager specification, or user-authored setup callback. A plugin distribution route may be considered separately if a future delivery context requires it, but it is not part of the initial replacement.

The pinned LazyVim fixture validates the provisioned entrypoint shape in a controlled environment. It does not replace live verification in the user's Neovim 0.12.4/LazyVim configuration. See [installation and replacement](installation.md) for the actual provisioning and live-check procedure.


## 10. Continuous integration

CI validates the independent layers in the test contract: scanner and buffer behaviour, installer output, shell-delivered payload bytes, formatter effects, and pinned LazyVim/plugin coexistence. The current workflow has five jobs:

- **Core scanner:** Lua scanner tests, parser-oracle fixtures, installer syntax and isolated repeat-execution tests.
- **Neovim buffer integration:** headless buffer-level editing tests.
- **Shell delivery:** payload-byte comparisons across Bash, Dash, and Zsh.
- **Formatter:** payload preservation under the configured `shfmt` invocation for Bash and POSIX-shell fixtures.
- **LazyVim integration:** a pinned container fixture exercising the generated per-filetype entrypoint shape and selected plugin coexistence.

The first four jobs do not require the pinned LazyVim container. The container job is an integration fixture, not a runtime dependency and not evidence of behaviour in the user's full workstation configuration.

See [the CI design](ci.md) for job boundaries, dependency policy, container role, and test-command prerequisites. CI invokes the same local test commands. Hosted success is recorded in [run 43205842260](https://github.com/incus-skills/nvim-heredoc/actions/runs/43205842260); this establishes the repository fixture results only. Live workstation verification remains outstanding.
