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
- Each test command has a known passing fixture and a deliberately failing, contract-specific negative control. `tests/expect-failure.sh` requires both non-zero exit and the expected assertion marker, so unrelated setup failures do not count as successful controls.

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
- `lua/nvim-heredoc/init.lua` provides the first Neovim buffer integration. It tracks changed line ranges with `nvim_buf_attach(on_lines)`, closes safe incomplete managed heredocs on `InsertLeave`/normal-mode change, re-scans pending heredocs in declaration order, and prefixes only the changed/body-range intersection for incremental edits.

- The live-editing path inserts a safely derived closer immediately below the active first body line when the `on_lines` change notification observes Enter after an incomplete `<<-` opener. It re-scans the buffer and applies structural indentation to the changed body range without waiting for `InsertLeave`. The existing `InsertLeave` fallback remains for buffers opened with an already-incomplete heredoc. The headless live-editing regression is isolated in `tests/lua/live_insert_spec.lua` and uses queued `nvim_input` plus timer-delayed assertions so Neovim's input loop and scheduled callbacks run between observations. It verifies that Enter creates the body prefix and reserves the closer while Insert mode remains active, that typed payload appears after the structural TAB while still in Insert mode, and that multi-line paste preserves payload indentation. Do not use `nvim_feedkeys(..., "x")` as evidence of live Insert-mode behaviour: draining the entire typeahead sequence inside the synchronous test can leave the test observing Normal mode instead of the live transition. Do not infer insertion position from the Insert-mode byte column; the regression verifies the actual resulting bytes.
- Headless buffer tests cover automatic closer insertion, body-space preservation, already-prefixed lines, ordinary heredoc non-interference, space-indented opener refusal, multiple queued managed heredocs, changed-range isolation, repeated notifications, and cursor preservation. All four CI jobs passed with Neovim 0.9.5 in run 43152169536.
- Ordinary `<<` heredocs are queued and consumed so their body text is not scanned as shell code; they are not returned as managed regions.
- Initial cases cover quoted delimiters, declaration-order queues, comments, quoted/escaped operators, here-strings, line continuations, tab-stripping terminators, and incomplete heredocs.
- Shell-delivery fixture and runner are present. GitHub Actions run 43150720234 passed the payload comparison with Bash 5.2.21, Dash, and Zsh 5.9.
- Formatter payload-comparison fixture passed in run 43150720234 with shfmt 3.8.0 for the Bash and POSIX-shell-subset fixtures. This is fixture-specific evidence, not a general guarantee. The test uses the configured `shfmt -i 0 -p` invocation in default language mode because shfmt rejects combining `-p` with `-ln`.
- Core scanner and pure editing-helper tests, including incomplete-opener closer construction, idempotent prefixing of empty/space/tab lines, ambiguity-stop, arithmetic contexts/expansions, ordinary and nested command substitutions, space-indented-opener cases, and valid empty quoted delimiter cases, passed under Lua 5.1.5 in run 43153320144.
- The four-job GitHub Actions workflow (core, buffer integration, shell delivery, formatter) passed in run https://github.com/incus-skills/nvim-heredoc/actions/runs/43153320144.
- Scanner result fields and current lexical limits are documented in [scanner interface](../../docs/scanner.md).

### Known prototype limits
- Added contract-specific negative controls for all five test commands. They verify that ordinary `<<` is not classified or edited (core, buffer, LazyVim), that `<<-` removes a leading TAB at shell delivery, and that shfmt preserves the delivered payload. The shared `tests/expect-failure.sh` requires the expected assertion marker as well as a non-zero exit, so setup failures cannot masquerade as successful negative controls. All five jobs passed with these controls enabled in [run 43196642359](https://github.com/incus-skills/nvim-heredoc/actions/runs/43196642359); each job log records its expected negative-control PASS line.

- This is not a complete shell parser. Command substitutions, backtick substitutions, multiline quoted commands, and other unsupported contexts are not yet recognised safely.
- Changed-range notifications are tracked through `nvim_buf_attach(on_lines)`. Pending notifications retain disjoint ranges separately and merge only overlapping or adjacent ranges. Before merging, earlier ranges are rebased through each subsequent edit's `(firstline, lastline, new_lastline)` line-count change. Headless regressions cover edits before an earlier pending range that insert and delete lines; overlapping replacements with line-count changes; a replacement spanning multiple disjoint pending ranges; and insertion at a pending-range boundary. They assert that untouched neighboring lines are not redirected into the changed range. This does not use extmarks; partial notifications, less common buffer mutation paths, and broader rapid-edit sequences still need testing.
- The headless Neovim runners now explicitly propagate Lua test failures with non-zero process exits; a trailing `qa!` had previously masked an earlier `:lua` error. The pinned LazyVim fixture runs its interactive test body after startup command processing, then exercises real mini.pairs quote insertion and the Blink buffer-source completion popup inside a managed heredoc. All five jobs passed with the insertion/deletion rebasing tests, interactive plugin checks, and negative controls in [run 43198320233](https://github.com/incus-skills/nvim-heredoc/actions/runs/43198320233).
- Added valid-but-unsupported Bash grammar fixtures for backtick substitution and heredoc redirection inside command substitution. CI parses them with mvdan/sh through `shfmt --to-json`; Lua tests separately assert uncertainty and prohibit editable regions. Parser validity is an independent syntax oracle, not permission to edit and not a runtime dependency. The corrected parser-oracle step and all five CI jobs passed in [run 43202359922](https://github.com/incus-skills/nvim-heredoc/actions/runs/43202359922); the core log confirms both fixtures parsed and the scanner suite plus its negative control passed.
- The Lua scanner tests are run in GitHub Actions; neither Lua nor Neovim is installed in the current development container.
- The local diagnostic script at `tests/diagnostics/inspect-lazyvim.sh` was run against the target workstation. Its output is recorded in [the plugin compatibility inventory](../../docs/plugin-compatibility.md), including exact LazyVim, mini.pairs, blink.cmp, conform.nvim, lazy.nvim, Treesitter, and Neovim revisions.
- Exact source inspection confirmed mini.pairs' global and buffer-local disable variables, blink.cmp's `vim.b.completion` control and `enabled` callback, and Conform's per-buffer `format_on_save` callback. The mini.pairs and Blink controls are buffer-wide; no region-scoped disable API was established. No suppression has been added.
- Added `ci/lazyvim/Dockerfile`, `ci/lazyvim/versions.env`, and `ci/lazyvim/init.lua`, plus `tests/run-lazyvim.sh` and `tests/lua/lazyvim_spec.lua`. The fixture loads the checked-out plugin alongside the pinned LazyVim core and selected plugin revisions, without the legacy `after/ftplugin` implementation. It checks that mini.pairs mappings and Blink completion remain enabled in managed heredoc buffers, ordinary `<<` remains unchanged, and Conform's actual shfmt path preserves delivered payload bytes. Zsh is not assigned to shfmt.
- Extended `tests/lua/lazyvim_spec.lua` to send a real insert-mode quote keystroke through mini.pairs in both ordinary shell code and a managed heredoc body. The assertions verify pair insertion and byte preservation after the plugin's scheduled changed-range processing. All five CI jobs, including this interactive mini.pairs test, passed in [run 43195452621](https://github.com/incus-skills/nvim-heredoc/actions/runs/43195452621). The fixture now also triggers Blink's real buffer-source completion menu from inside a managed heredoc body and verifies that the menu becomes visible with at least one candidate.
- Corrected deferred range aggregation so disjoint edits do not authorise prefixing unchanged lines between them. All five CI jobs passed with the new buffer regression test in [run 43195634691](https://github.com/incus-skills/nvim-heredoc/actions/runs/43195634691), including the pinned LazyVim container job.
- The expanded LazyVim fixture, including the actual Blink completion popup test, passed all five jobs in [run 43195871478](https://github.com/incus-skills/nvim-heredoc/actions/runs/43195871478).
- The first five-job CI run, including the new container build and headless plugin coexistence test, passed in [run 43175124220](https://github.com/incus-skills/nvim-heredoc/actions/runs/43175124220). This is a controlled LazyVim-core/selected-plugin fixture, not a full LazyVim starter installation or the user's complete private configuration.

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
