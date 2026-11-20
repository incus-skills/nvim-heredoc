# Task 001 — Return-local bounded heredoc editing

**Status:** pre-release field-validation stage — core functionality is substantially implemented; field verification, remaining edge cases, and opportunities for simplification remain open  
**Priority:** foundational  
**Scope:** validate and simplify the managed <<- editing path around the established Return-local bounded-scope contract. Do not expand this task into a general shell parser or document-wide heredoc tracking system.

## Governing decision

The interactive commitment point is **Return after the user has completed a managed <<- opener**.

Typing the opener is not itself a request to create or track a closer. When Return is pressed:

1. Recognise the completed opener, its <<- operator, and delimiter.
2. Commit to the new heredoc by inserting its matching closer immediately.
3. Place the closer within the available enclosing shell structure (for example, before an existing function-closing brace), or at the natural end of a standalone construct.
4. Treat the inserted closer as the end of this heredoc's lexical input scope.
5. Treat all text between opener and closer as payload. Opener-looking text inside that body is not a competing heredoc declaration.

This decision supersedes the earlier framing in this task that made a shared, document-wide region model the authority for all editing integrations. The scanner remains a bounded lexical helper; it does not need to maintain identities and lifetimes for every heredoc in the document, search later candidate terminators to discover ownership, or reconstruct general shell structure.

Use existing shell indentation/structural context for function and compound-command layout where available. The plugin should calculate only the local information necessary to place the new closer. Do not build a second general shell indentation engine. If local placement is ambiguous, leave the buffer unchanged rather than widening the architecture.

The shell language's declaration-order semantics for multiple heredocs on one command remain valid and may remain covered by scanner/shell tests. They do not imply a document-wide obligation ledger for Return-local scope creation.

## Objective

The core heredoc editing and autoformatting objective is substantially implemented and is approaching pre-release field validation. Use the pre-release as a stable baseline in real LazyVim configurations. Identify remaining functional edge cases, environment-specific behaviour, efficiency issues, and opportunities for simplification. Preserve the established Return-local editing contract, payload bytes, and shell-delivery semantics.

This task is no longer a reason to hold the project in an open-ended core-development phase. Remaining work should be judged by whether it materially affects safe, predictable use of the existing feature. Nested heredoc indentation and embedded-language presentation/Tree-sitter injection are separate stretch goals and are not acceptance prerequisites for the pre-release.

## Required work

1. Audit the current production path against the governing decision above. Identify which mechanisms are strictly required for Return recognition, immediate closer insertion, local structural placement, body prefixing, cursor placement, and duplicate-event protection.
2. Separate unavoidable Neovim event/coalescing behaviour from architecture that attempts to reconstruct document-wide heredoc ownership.
3. Keep the lexical scanner bounded. Add grammar support only when a concrete supported use case and regression demonstrate the need.
4. Verify that Return after a completed opener inserts the matching closer before an existing enclosing structural closer, without synthesising or recreating that enclosing closer.
5. Verify that a standalone managed heredoc receives its closer at the appropriate local position.
6. Verify that body content resembling another heredoc opener remains payload once the Return-local closer has established the scope.
7. Verify shell delimiter rules: <<- strips leading TAB bytes for matching, not spaces; ordinary << does not strip leading TABs or spaces.
8. Preserve body spaces and relative indentation through typing and multi-line paste. Do not promise preservation of leading body TABs after shell execution because <<- strips them.
9. Ensure repeated/deferred callbacks cannot duplicate the closer or body prefix and that the Insert-mode cursor is positioned after the structural body prefix before payload typing.
10. Preserve existing managed <<- to << transition behaviour where it remains part of the supported contract, without allowing that compatibility path to dictate new-scope architecture.
11. Keep the layered scanner, buffer, live Insert-mode, shell-delivery, formatter, and plugin-coexistence tests. Amend tests only when a case asserts a superseded implementation mechanism rather than observable behaviour.
12. Record genuine lexical and editor-event limitations. Do not claim complete shell grammar support.
13. Run the documented test commands and CI. Distinguish hosted fixture results from live workstation and field verification.
14. Use pre-release field reports to prioritise genuine correctness defects, compatibility issues, performance concerns, and simplifications; avoid expanding scope merely because an adjacent capability is technically interesting.

## Acceptance criteria

- Return after a completed managed opener establishes the body and immediately inserts its matching closer.
- When an enclosing function/compound-command closer is already present, the heredoc closer is placed inside it; the plugin does not create or recreate the enclosing structural closer.
- The inserted closer bounds the body. Opener-looking payload lines are not reinterpreted as new heredoc openers.
- Delimiter matching follows the actual operator: <<- ignores leading TAB bytes but not leading spaces; ordinary << requires the delimiter at column zero.
- The delimiter is derived from the actual opener, not hard-coded.
- Structural indentation uses literal TAB bytes; body spaces and relative indentation remain intact.
- The cursor remains in Insert mode and after the body prefix before the user types payload.
- Subsequent Enter and multi-line paste preserve payload bytes and do not duplicate prefixes.
- Ordinary << and <<< remain unmanaged and byte-for-byte unaffected by managed editing actions.
- Existing scanner and buffer regressions remain green unless they explicitly require the superseded global ownership architecture.
- Shell-delivery tests demonstrate the bytes Bash, a POSIX shell, and Zsh receive where available.
- Formatter tests establish only the fixture-specific behaviour actually tested.
- Unsupported or ambiguous local syntax fails conservatively.
- CI results and live workstation observations are reported separately.

## Boundaries

- Do not introduce opener-time character-by-character recognition or a persistent obligation created merely by typing the opener.
- Do not add a document-wide heredoc identity ledger, retained scan history, global source-order ownership recovery, or a general shell structural parser unless a concrete regression proves it necessary for the Return-local contract.
- Do not reinterpret opener-looking body text as shell syntax after the local closer has established the body.
- Do not change the user's Neovim configuration.
- Do not globally disable completion or pair insertion.
- Do not add Zsh to shfmt formatting.
- Do not strip, normalise, or blindly replace pasted body whitespace.
- Do not expand shell grammar coverage merely to make the scanner appear comprehensive.

## Current architectural decisions

- Return after the completed managed opener is the commitment point.
- The plugin inserts the matching closer immediately; the inserted closer defines the new body's lexical boundary.
- Body text inside that boundary is payload, including text that resembles another opener.
- Other heredocs elsewhere in the document are not needed to establish this scope.
- Existing shell indentation machinery is preferred for enclosing function/compound-command context; plugin-owned structural reasoning is local and minimal.
- The scanner is a bounded lexical helper, not a document-wide source of heredoc identity and lifetime.
- Existing tests are retained as observable regression coverage. They do not make exploratory mechanisms into requirements.
- CI is layered; hosted test success is not proof of live workstation behaviour.

## Historical implementation record (non-normative)

The notes below preserve evidence and decisions from earlier implementation cycles. They are historical context, not additional architectural requirements. Where they describe retained scans, opener identity, declaration-order ownership recovery, or broad region-model machinery, apply the governing decision above: retain only what is demonstrably necessary for the Return-local contract.

## Implementation progress

### Return-local refactor in progress

- Added `scanner.parse_openers()` to recognise the completed command text without scanning the surrounding buffer or searching for a later terminator.
- The interactive path now intercepts the actual Insert-mode <CR> key through a buffer-local non-expression mapping. For a single safe managed <<- opener at end-of-line, it derives the closer from the actual delimiter and synchronously inserts the first body line plus closer in one edit, then positions the cursor after the body prefix. This is the commitment event; deferred on_lines ranges are no longer used to infer that a Return occurred. The closer bounds the body independently of unrelated later heredocs using the same delimiter.
- For other Return keys, the mapping delegates to Blink completion acceptance when its menu is visible, then MiniPairs' Return callback when available, otherwise native Return. Expression mappings were rejected because Neovim's textlock prevents their callbacks from editing the buffer.
- Multiple heredoc redirections on one command remain conservative in this Return-local path; the parser returns their records, but the editor does not guess the distinct body/terminator placement.
- Added core tests for local opener recognition, delimiter derivation, literal TAB prefixes, unsupported indentation, ordinary `<<`, and here-string rejection. The existing live function-boundary test already places a later independent `<<` heredoc with the same `EOF` delimiter after the new opener and asserts that the new closer is inserted before the existing function brace and original source.
- Full five-job hosted workflow [#44359228055](https://github.com/incus-skills/nvim-heredoc/actions/runs/44359228055) passed on implementation head `dc410bd`, including Neovim buffer integration, core scanner, shell delivery, formatter payload preservation, and pinned LazyVim/MiniPairs/Blink integration. The current head only adds this validation note; its documentation-only workflow is pending. Workstation verification remains pending. The compatibility scan/snapshot path remains for existing-buffer recovery and managed operator transitions; it is not used to commit a new Return-local scope.

### Present

- The scanner now exposes `heredocs` for all lexically recognised heredoc operators while retaining `regions` as the managed `<<-` subset. Buffer snapshots use this distinction to recognise an operator change on an already managed heredoc: `<<-` to `<<` removes the plugin’s body prefix and opener-aligned TABs from the terminator; `<<` to `<<-` reapplies them. The transition is matched by opener line, queue position, and delimiter identity. A headless regression exercises both directions, including a blank body line and nested space indentation.

- `lua/nvim-heredoc/scanner.lua` provides an initial buffer-independent lexical scan and a shared region record for completed or incomplete managed heredocs. The record distinguishes `opener_safe` from full-region `editable` so a lexically certain incomplete opener can support closer construction without authorising body edits.
- `lua/nvim-heredoc/editing.lua` provides pure helpers for constructing the structural closer line and idempotently prefixing a caller-supplied line range.
- `lua/nvim-heredoc/init.lua` provides the first Neovim buffer integration. It tracks changed line ranges with `nvim_buf_attach(on_lines)`, closes safe incomplete managed heredocs on `InsertLeave`/normal-mode change, re-scans pending heredocs in declaration order, and prefixes only the changed/body-range intersection for incremental edits.

- The live-editing path inserts a safely derived closer immediately below the active first body line when the `on_lines` change notification observes Enter after an incomplete `<<-` opener. It re-scans the buffer and applies structural indentation to the changed body range without waiting for `InsertLeave`. The existing `InsertLeave` fallback remains for buffers opened with an already-incomplete heredoc. The headless live-editing regression is isolated in `tests/lua/live_insert_spec.lua` and uses queued `nvim_input` plus timer-delayed assertions so Neovim's input loop and scheduled callbacks run between observations. It disables Neovim's own indentation, verifies that a second Enter creates a new TAB-prefixed line before InsertLeave, types payload on that line, and uses `nvim_paste()` for a multi-line paste while Insert mode remains active. The test exposed a real cursor defect: inserting a TAB through the buffer API left the Insert-mode insertion point before it, so the next typed bytes appeared before the TAB. The integration now queues a literal Right key at the front of typeahead after prefixing the active cursor line, advancing the insertion point past the structural TAB without forcing a Normal-mode cursor position. The regression asserts payload bytes and Insert mode before leaving it. Do not use `nvim_feedkeys(..., "x")` as evidence of live Insert-mode behaviour: draining the entire typeahead sequence inside the synchronous test can leave the test observing Normal mode instead of the live transition.
- The strengthened live-editing regression and all four other workflow jobs passed with Neovim 0.9.5 in [run 43231942915](https://github.com/incus-skills/nvim-heredoc/actions/runs/43231942915). The Neovim job log records both the buffer integration suite and `live Insert-mode buffer tests: PASS`; the pinned LazyVim/plugin coexistence job also passed. This is headless CI evidence, not yet confirmation in the user's interactive configuration.
- A `TextChangedI` experiment attempted to process pending changed ranges synchronously during Insert mode, and the accompanying headless test queued Enter plus payload without an intervening wait. Although all five CI jobs passed in [run 43235886821](https://github.com/incus-skills/nvim-heredoc/actions/runs/43235886821), the user then reported that automatic closer insertion had disappeared in the interactive configuration. The `TextChangedI` autocmd has therefore been reverted. The test has also been returned to a deferred observation so it no longer claims to establish immediate live indentation. This is evidence that the headless fixture does not yet reproduce the user's runtime event ordering; do not treat live Insert-mode timing as solved.
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

- Follow-up after the closer regression: removed `TextChangedI` from the buffer autocmd list, retained `TextChanged` plus the scheduled `on_lines` fallback, and restored a regression test that waits for the existing deferred prefix operation before typing. The closer reservation assertion after the opener remains. Local verification of automatic closer insertion is now the immediate acceptance check; investigate a different Insert-mode event strategy only after that behaviour is confirmed restored.