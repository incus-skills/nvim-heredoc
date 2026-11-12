# Task 001 — Shared region model and executable core

**Status:** active — initial scanner prototype and first validation commands added  
**Priority:** foundational  
**Scope:** establish and test the shared lexical model for managed `<<-` heredoc regions. Do not produce a user-facing installer yet.

## Objective

Build a conservative, buffer-independent Lua scanner/prototype that identifies managed `<<-` heredoc regions in Bash, POSIX `sh`, and Zsh source without requiring Treesitter. Use the same scanner for all three. Treesitter may provide optional structural assistance, but must not be a runtime dependency.

The scanner is the common authority for later editing mechanisms. Automatic closer insertion, indentation, paste preservation, auto-pairs, completion, and formatter integration must consume its region model rather than independently guessing the active heredoc.

## Required work

1. Inspect the repository state and establish the implementation/test layout.
2. Define a scanner interface returning opener span, operator kind, original and quote-removed delimiter, quote/expansion state, logical command boundary, queue position, body range, terminator, structural indentation bytes, and confidence/ambiguity information.
3. Implement operator recognition that ignores quoted/escaped contexts and comments, distinguishes `<<-`, `<<`, and `<<<`, and handles quoted/escaped delimiters.
4. Model multiple pending heredocs on a command in declaration order, including command continuation before body consumption.
5. Resolve nested shell constructs sufficiently to avoid treating an earlier completed heredoc or a nearby opener as the active region.
6. Make malformed or ambiguous input fail conservatively without authorising source mutation.
7. Add buffer-independent unit tests for scanner and region results.
8. Prototype region-based editing behaviour: closer placement from the opener's structural TAB prefix, and changed-range paste handling that preserves every existing byte and relative indentation.
9. Ensure repeated/partial/ambiguous change notifications cannot duplicate prefixes or corrupt inserted text. If the changed range cannot be established, leave it unchanged.
10. Add shell-delivery fixtures that demonstrate actual `<<-` tab stripping and payload bytes.
11. Add formatter fixtures for `shfmt -i 0 -p` on Bash and POSIX `sh`, comparing payload bytes before and after formatting. Zsh must not be assigned to `shfmt`.
12. Record unresolved grammar and editing limits explicitly rather than claiming complete shell parsing.
13. Define stable local commands for core, shell-delivery, formatter, and headless LazyVim integration tests; CI must call these commands rather than duplicate test logic.

## Acceptance criteria

- Ordinary `<<` and `<<<` are never classified as managed heredocs.
- Operators inside quotes, escaped text, and comments are not detected as heredoc openers.
- Multiple heredocs are associated with their correct body blocks in declaration order.
- Quoted delimiters are matched correctly while preserving source spelling.
- Nested constructs and command continuations do not cause nearest-opener misclassification.
- Structural indentation is represented by TAB bytes; body spaces and relative indentation are preserved.
- Tests prove that leading body tabs are stripped by the shell and leading spaces are retained.
- Paste tests operate on complete changed ranges and demonstrate byte preservation, including empty and whitespace-only lines.
- The tests demonstrate what Bash, a POSIX shell, and Zsh actually receive where those shells are available.
- Formatter tests establish the effect of `shfmt -i 0 -p` on heredoc payloads; no assumption of preservation is accepted without evidence.
- The scanner does not depend on Treesitter being installed or able to parse an incomplete buffer.
- Test output is reproducible with documented commands.
- A layered CI workflow runs core, shell-delivery, and formatter tests independently of LazyVim, with LazyVim integration isolated in a pinned container environment.
- Each test command has a known passing fixture and a deliberately failing fixture that proves regressions fail the relevant job.

## Boundaries

- Do not change the user's Neovim configuration.
- Do not implement auto-pair/completion suppression until the actual installed plugin APIs have been inspected.
- Do not add Zsh to `shfmt` formatting.
- Do not strip, normalise, or blindly prefix pasted body whitespace.
- Do not write an installer in this task. The repository currently has no tracked installer; a versioned installer is a later delivery mechanism and must package the tested implementation rather than become its only source.

## Current architectural decisions

- Shared Lua lexical scanner is authoritative for all three shell filetypes.
- Treesitter availability is optional assistance only. The latest user diagnostic reports parsers available for Bash, `sh`, and Zsh; earlier reports of unavailable `sh`/Zsh parsers are superseded.
- Editing is region-based. Integrations consume one shared region model; they do not independently search backwards for the nearest opener.
- Structural indentation uses leading TAB bytes. Body spaces are payload and remain intact. Leading body TAB bytes are stripped by `<<-` at shell execution.
- Paste handling must identify the full changed range and preserve bytes. If range identification is uncertain, do nothing.
- `shfmt` is assigned only to Bash and POSIX `sh`; Zsh is excluded.
- Formatting is independently validated against actual heredoc payload bytes.
- CI is layered; the core and shell-semantic test paths do not require the LazyVim container. The container is an integration environment, not a runtime dependency.

## Implementation progress

### Present

- `lua/nvim-heredoc/scanner.lua` provides an initial buffer-independent lexical scan and a shared region record for completed or incomplete managed heredocs. The record distinguishes `opener_safe` from full-region `editable` so a lexically certain incomplete opener can support closer construction without authorising body edits.
- `lua/nvim-heredoc/editing.lua` provides pure helpers for constructing the structural closer line and idempotently prefixing a caller-supplied line range.
- `lua/nvim-heredoc/init.lua` provides the first Neovim buffer integration on `InsertLeave` and `TextChanged`. It closes safe incomplete managed heredocs, re-scans pending heredocs in declaration order, and prefixes the body of completed regions.
- Headless buffer tests cover automatic closer insertion, body-space preservation, already-prefixed lines, ordinary heredoc non-interference, space-indented opener refusal, and multiple queued managed heredocs. All four CI jobs passed with Neovim 0.9.5 in run 43151626549.
- Ordinary `<<` heredocs are queued and consumed so their body text is not scanned as shell code; they are not returned as managed regions.
- Initial cases cover quoted delimiters, declaration-order queues, comments, quoted/escaped operators, here-strings, line continuations, tab-stripping terminators, and incomplete heredocs.
- Shell-delivery fixture and runner are present. GitHub Actions run 43150720234 passed the payload comparison with Bash 5.2.21, Dash, and Zsh 5.9.
- Formatter payload-comparison fixture passed in run 43150720234 with shfmt 3.8.0 for the Bash and POSIX-shell-subset fixtures. This is fixture-specific evidence, not a general guarantee. The test uses the configured `shfmt -i 0 -p` invocation in default language mode because shfmt rejects combining `-p` with `-ln`.
- Core scanner and pure editing-helper tests, including incomplete-opener closer construction, idempotent prefixing of empty/space/tab lines, ambiguity-stop, arithmetic-context, and space-indented-opener cases, passed under Lua 5.1.5 in run 43151269417.
- The initial three-job GitHub Actions workflow passed all three jobs in run https://github.com/incus-skills/nvim-heredoc/actions/runs/43151269417.
- Scanner result fields and current lexical limits are documented in [scanner interface](../../docs/scanner.md).

### Known prototype limits

- This is not a complete shell parser. Command substitutions, backtick substitutions, multiline quoted commands, and other unsupported contexts are not yet recognised safely.
- The first Neovim integration exists, but it currently prefixes the full recognised body range rather than tracking the precise changed/pasted range. Extmark-based range tracking and cursor-preservation tests remain outstanding.
- The Lua scanner tests have been authored but not executed in the current development environment because neither Lua nor Neovim is installed here.
- The LazyVim container job is deferred until plugin coexistence tests and a pinned LazyVim environment are ready.

Do not describe the scanner as production-ready or authorise source mutation from uncertain results.

## Handoff

When complete, report:
1. Files added/changed.
2. Scanner and region model, including known limits.
3. Editing and paste behaviour implemented.
4. Tests run and exact results.
5. Shells and formatters available and tested.
6. Unresolved cases.
7. CI commands/workflow status, including whether the container integration job has been exercised.
8. Recommended next task.

Keep task in `active/` until implementation, tests, and handoff are complete.
