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

The displayed width of a structural TAB is determined by the buffer's `tabstop`; it is not a conversion to spaces. The opener may retain leading spaces when its visual indentation column is exactly representable by leading TABs at that tabstop. In that case, the editor leaves the opener bytes unchanged and derives two prefixes: an opener-aligned structural prefix for the terminator, and a body prefix with one additional literal TAB. For example, with `tabstop=2`, an opener indented by two spaces maps to one literal TAB for the terminator and two literal TABs for body lines. If the opener's visual column cannot be represented exactly by leading TABs (for example, three spaces at `tabstop=2`), the region remains non-editable rather than being silently shifted. A visually nested example must not be interpreted as evidence that literal leading spaces on a terminator are valid.

For example, the structural TABs below are literal TAB bytes; the spaces inside the body are payload:

```sh
some_function() {
	if some_condition; then
		cat <<-'EOF'
			This content is visually indented one TAB beyond the opener.
			Pasted content retains its relative indentation.

			Nested-looking content:
			  level two
			  level two
		EOF
	fi
}
```

The shell removes the leading TABs from each body line and the terminator. The extra body TAB establishes visual indentation in the editor but is also stripped by the shell; the two spaces before each `level two` line remain in the payload.

These rules need explicit regression tests. The editor must not claim to preserve payload tabs that the shell itself strips.

## 3. Governing interaction model: Return establishes a bounded scope

The interactive contract is deliberately local.

1. The user completes a managed <<- opener.
2. The user presses Return.
3. The plugin recognises the completed opener at this transition, resolves its delimiter and <<- mode, and commits to creating the matching closer.
4. The plugin inserts that closer immediately, at the appropriate local position: within the available enclosing shell structure (for example, before an existing function-closing brace), or at the natural end of a standalone construct.
5. The inserted closer defines the end of the new heredoc's lexical input scope. The body is the text between this opener and this closer.

The plugin does not need to recognise and maintain an opener lifecycle character-by-character while the delimiter is being typed. Nor does it need a document-wide ledger of heredocs, stable identities for every opener, or a search through later candidate terminators to discover which closer belongs to the newly opened heredoc. The closer is created at the commitment point; it is not discovered later.

An opener-looking line inside the established body is payload, not a competing shell command or heredoc declaration. A delimiter-looking line is governed by the shell's actual delimiter matching rules; it does not acquire ownership of the new scope merely because it appears later in the document. Other heredocs elsewhere in the buffer are outside the scope-establishment decision.
This opacity applies recursively to interpretation, not to shell execution: the editor does not parse embedded script text as active shell syntax. A Return pressed on any line inside an existing heredoc body must remain a payload edit, even when that line contains a valid-looking managed opener. The containing heredoc must not create a nested closer or impose its shell indentation rules on the embedded script.

**The lexical-zone boundary also governs syntax representation.** Content inside an established heredoc body is not active syntax belonging to the containing shell document. In particular, an inner heredoc opener or delimiter-looking line whose spelling does not match an enclosing heredoc delimiter under that enclosing operator's shell matching rules (for example, inner `FOE` cargo inside outer `EOF`) must not be adopted by the containing Bash syntax parse as an outer-shell construct or terminator. A same-spelling line that actually matches the enclosing delimiter is not payload under Bash shell-delivery semantics; it is the enclosing heredoc's terminator and is covered by the separate delimiter-collision distinction below. The payload may eventually be represented as an embedded language or as opaque content; that presentation choice is separate from the boundary itself. The current Tree-sitter highlighting behaviour that adopts an inner `EOF` as a Bash heredoc terminator does not satisfy this policy and remains an outstanding visual-representation gap.

This is not a general shell parser design. The plugin should use existing shell indentation/structural context for function and compound-command layout where available. Its own structural work should be limited to the local information genuinely needed to place the newly committed closer. If that local placement cannot be established safely, leave the buffer unchanged rather than reconstructing the whole document.

The shell itself permits multiple heredoc redirections on one command and consumes them in declaration order. That language fact may remain represented in scanner fixtures where relevant, but it does not justify a document-wide ownership model for the Return-local editing path.

## 4. Bounded lexical recognition and editing responsibilities

The scanner is a supporting lexical recogniser, not the authority for a global document-wide region graph. For the Return transition it needs enough information to establish:

- that the current completed opener is a managed <<- redirection;
- the delimiter spelling and quote-removed delimiter value;
- the opener's structural indentation and the TAB prefixes required by <<-;
- the start of the body created by Return;
- whether the local closer placement is safe in the current structural context.

The scanner may retain broader lexical coverage used by existing tests and by safe handling of ordinary heredoc payload. Such coverage is a bounded implementation aid. It must not turn into a requirement to track every heredoc's identity or lifetime across the document.

Editing responsibilities are correspondingly narrow:

- **Closer commitment:** create the matching closer on Return, rather than waiting for a later scan to discover a candidate terminator.
- **Structural placement:** put the closer inside an already-present enclosing boundary when that is the correct local placement; do not invent or recreate a function/compound-command closer.
- **Body indentation:** add the managed body TAB prefix while preserving payload spaces and relative indentation.
- **Terminator indentation:** align the closer with the opener using literal TAB bytes that <<- will strip.
- **Existing managed transition:** preserve the established behaviour for changing an already-managed opener between <<- and <<, but do not let this compatibility path define the architecture of new Return-local scope creation.
- **Paste preservation:** operate on the actual changed range and preserve existing bytes. This is a separate buffer-editing concern, not a reason to build a global heredoc identity system.

Ordinary << heredocs and here-strings (<<<) remain unmanaged. They must not be modified by managed editing actions.

## 5. Interactive event handling and paste preservation

The Return event is the semantic commitment point. Buffer-change callbacks are deferred and may coalesce a rapid sequence of Returns and payload keystrokes into one range; they are therefore not a reliable source of the individual commitment events.

The interactive path uses a buffer-local, non-expression Insert-mode <CR> mapping. Expression mappings run under Neovim's textlock and cannot perform the required buffer edit. Before recognising an opener, the mapping uses the scanner's bounded lexical result to determine whether the cursor is already inside an existing heredoc body (managed <<- or ordinary <<). If it is, Return is a literal line split: the plugin does not parse that line as shell syntax and does not delegate indentation to the shell indentexpr, autoindent, or MiniPairs. Blink may still consume Return for an explicitly visible completion menu. The containing heredoc may contribute its fixed structural TAB prefix, which <<- strips, but that prefix must not be derived cumulatively from preceding payload lines or alter the payload's relative spaces.

Outside an existing payload, the mapping examines only the current line when the cursor is at its end. For exactly one safe managed <<- opener, it synchronously inserts the first body line and matching closer in one edit, then places the Insert-mode cursor after the body prefix. The new closer immediately bounds the body. It does not wait for on_lines, a scheduled scan, or a later candidate terminator.

For non-payload, non-managed Return, the wrapper delegates to Blink's accept action when its completion menu is visible, then to MiniPairs' Return behaviour when available, and otherwise feeds native Return ahead of the remaining typeahead. This delegation is part of plugin coexistence, not a second heredoc parser. The deferred changed-range path must apply the same payload exclusion before attempting Return-local opener recognition.

- Distinguish Return immediately after the completed opener from ordinary later body edits. Do not use a broad changed-range coincidence as a substitute for the event's meaning.
- Insert the closer before the existing enclosing structural closer when that is the correct local placement. Do not synthesize a missing function brace or other enclosing construct.
- Establish the first body TAB prefix and keep the Insert-mode cursor after it before the user types payload.
- Repeated callbacks must not duplicate the closer or body prefix.
- Later body edits and multi-line paste must not cause opener-looking payload to be reinterpreted as shell syntax.
- Return inside an existing heredoc body must split payload literally and bypass inherited shell indentation; fixed <<- structural TAB prefixing may remain, but embedded payload indentation must not staircase.
- Paste handling must identify the complete changed range. It must preserve relative indentation, including spaces on whitespace-only lines; do not trim or normalise payload whitespace.
- Empty lines, space-only lines, and tab-containing lines require explicit tests. Leading payload TABs are stripped by the shell under <<- and cannot be promised as preserved payload indentation.
- If the current opener, local placement, or changed range is ambiguous, leave the text unchanged rather than searching the document for a plausible substitute.

Normal shell indentation, pair insertion, and completion should coexist. Do not introduce buffer-wide suppression or a second general structural indentation engine without a demonstrated, region-specific need.

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

Use a bounded lexical scanner rather than requiring Treesitter. It supports local opener/delimiter recognition and conservative payload handling; it is not a mandate to construct a document-wide heredoc ownership graph. It must account for:

- Single-quoted, double-quoted, and escaped text when detecting operators.
- Comments, without treating `#` inside words/quotes as a comment.
- Here-strings versus heredoc operators.
- Quoted and escaped delimiters.
- Command continuations and the point at which pending heredoc bodies begin.
- Shell declaration-order semantics for multiple heredocs attached to one command, where covered by the supported lexical subset; this does not imply cross-document obligation tracking.
- Nested shell constructs sufficiently to avoid false operator detection.

The scanner should expose only the bounded lexical information needed by its consumers and explicitly record unsupported or ambiguous grammar cases. It must not authorise edits merely because a line resembles a heredoc opener. Once Return has established a closer, opener-looking text within that bounded body is payload.

Treesitter may be used as an optional cross-check or structural aid when a parser is available and successfully parses the relevant buffer. The lexical scanner remains the source for supported heredoc operator and delimiter recognition; it is not the authority for general shell structural indentation or document-wide heredoc ownership. It must work when Treesitter is absent, unavailable for a filetype, or unable to parse an incomplete editing buffer.

For syntax presentation, optional parser use must not override the established payload boundary: the containing shell parse must not claim payload content as active shell syntax. A future injection or other region-aware presentation mechanism may assign a contained language, or leave the region opaque, but it must consume the established body range. Parser availability remains optional for structural recognition and editing; this does not make incorrect outer-shell interpretation of payload an accepted visual result.

The first implementation in `lua/nvim-heredoc/scanner.lua` is a deliberately bounded lexical prototype. It handles simple command lines, line continuations, comments, quotes, escaped operators, ordinary heredoc body skipping, declaration-order queues, arithmetic expansions, and ordinary command substitutions without nested heredocs. A heredoc redirection inside command substitution, backtick substitution, multiline quoted commands, and other unsupported contexts remain uncertain and must not be edited. It does not claim complete shell grammar coverage. The supported subset and diagnostics must expand only alongside regression tests.

## 8. Validation contract

Validation has independent layers.

### Buffer-level tests

The existing scanner and buffer tests remain applicable unless an individual case is explicitly superseded. Their role is to validate the bounded Return-local contract, shell lexical rules, and safe non-interference—not to require the implementation to retain every investigative mechanism used to reach that contract.

Verify exact bytes, local scope boundaries, and cursor placement for:

- A single indented `<<-` heredoc.
- Return after an opener inside an indented function/conditional, with the new closer inserted before the existing structural closer.
- Body lines resembling other heredoc openers, proving that they remain payload inside the established scope.
- Heredoc cargo (an embedded script containing its own heredoc) should use an inner delimiter that does not collide with any enclosing delimiter under the enclosing heredoc's matching rules. This keeps the fixture's intended inner terminator from also terminating the outer shell heredoc. For `<<-`, leading TAB bytes are stripped for matching; a hard-left matching delimiter also terminates it.
- Keep a separate same-delimiter collision fixture when testing shell-delivery/editor-region differences. Do not use that case as the ordinary lexical-containment fixture or interpret an outer parse ending at the first matching line as a parser defect without accounting for Bash delimiter semantics.
- Delimiter-looking lines with valid and invalid TAB/space indentation, proving that shell delimiter rules remain authoritative.
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

The canonical implementation is the tested Lua source in the repository and
is distributed as a normal Neovim plugin. The supported installation path is
lazy.nvim, using the repository specification with the supported filetypes
(`bash`, `sh`, and `zsh`) and an empty `opts` table.

The plugin owns its runtime loading and buffer attachment through
`require("nvim-heredoc").setup()`. It does not require copied implementation
modules, generated `after/ftplugin` files, a shell provisioner, or manual
`runtimepath` changes. The local LazyVim integration fixture exercises the
same lazy.nvim loading contract using a local repository checkout.

There are no user-facing setup options at present. The supported filetypes
and automatic closer behaviour are part of the current implementation
contract, not user configuration defaults. The earlier provisioner forced
`expandtab`, `tabstop`, `softtabstop`, and `shiftwidth` to work around an
implementation that required the opener to be positioned at column zero.
That workaround is obsolete: opener positioning no longer requires a leading
TAB before the opener or changes to those options. The plugin does not set
them. `tabstop` remains an input to visual-column calculations when analysing
an opener that is indented with spaces; it is read, not changed.

## 10. Continuous integration

CI validates the independent layers in the test contract: scanner and buffer
behaviour, shell-delivered payload bytes, formatter effects, and pinned
LazyVim/plugin coexistence. The current workflow has five jobs:

- **Core scanner:** Lua scanner tests and parser-oracle fixtures.
- **Neovim buffer integration:** headless buffer-level editing tests.
- **Shell delivery:** payload-byte comparisons across Bash, Dash, and Zsh.
- **Formatter:** payload preservation under the configured `shfmt`
  invocation for Bash and POSIX-shell fixtures.
- **LazyVim integration:** a pinned container fixture loading the plugin
  through lazy.nvim's local plugin specification and exercising selected
  plugin coexistence.

The first four jobs do not require the pinned LazyVim container. The container
job is an integration fixture, not a runtime dependency and not evidence of
behaviour in the user's full workstation configuration.

See [the CI design](ci.md) for job boundaries, dependency policy, container
role, and test-command prerequisites. CI invokes the same local test
commands. Hosted success establishes the repository fixture results only;
live workstation verification remains separate.
