# Task 001 — Shared region model and executable core

**Status:** active  
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
