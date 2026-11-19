# Task 002 — Enforce lexical-zone boundaries in syntax representation

**Status:** active — non-colliding cargo fixture added; parser-tree diagnosis pending  
**Priority:** diagnostic — the previously reported mismatch was associated with a same-delimiter collision; a non-colliding parser result still requires direct tree/capture inspection  
**Scope:** determine and implement a syntax-presentation path that prevents the containing shell parser from claiming established heredoc payload as active shell syntax. Do not change the Return-local editing architecture or select a payload-language strategy by assumption.

## Governing policy

The adopted policy is recorded in [the design contract](../../docs/design.md) and [future development context](../../docs/future-development-context.md):

- An established heredoc body is a lexical zone distinct from the active syntax of its containing shell document.
- The boundary is authoritative for both editing behaviour and syntax representation.
- The containing shell parse must not adopt a non-colliding inner payload heredoc delimiter as an outer-shell heredoc terminator or construct. If an inner-looking line also matches the enclosing delimiter under Bash's rules, it is the enclosing shell heredoc terminator; retain that as a separate collision case rather than calling it payload containment.
- Payload classification is independent of structural recognition. An unknown payload must not silently become active Bash syntax.
- The visual representation may eventually be a contained-language parse/injection or opaque content. The project has not selected that strategy.
- The existing scanner/closer boundary is the structural source of truth. A syntax parser or injection query must not independently redefine it.

**Defer how the payload is represented, not whether its lexical boundary is respected.**

## Current investigation outcome and boundary

The non-colliding cargo fixture uses distinct outer (`EOF`) and inner (`FOE`) delimiters. It is the valid fixture for exercising the plugin's lexical-zone and shell-delivery behaviour. The same-delimiter case remains a separate shell-delivery collision: under Bash `<<-` matching rules, a hard-left line matching the outer delimiter terminates the outer shell heredoc too. Do not treat that collision alone as evidence of a parser defect.

The current work establishes the distinction between the plugin's scanner-derived region, the bytes delivered by the shell, and syntax presentation. The existing test suite covers scanner recognition, editor behaviour, shell delivery, formatter preservation, and plugin coexistence. It does not claim to establish Tree-sitter parse-tree containment.

**Tree-sitter parse-tree boundary diagnosis and syntax-presentation implementation are explicitly deferred to future development.** They are not the next step or an acceptance prerequisite for the current investigation. No parser tree, capture, injection, grammar, or highlighting strategy should be changed as part of closing the present fixture/test clarification.

## Initial source inspection

The pinned nvim-treesitter revision recorded in the project compatibility inventory is `19bdfc04f40ed2ccb3340591d125f759b0406875`. At that revision:

- `runtime/queries/bash/highlights.scm` captures both `(heredoc_start)` and `(heredoc_end)` as `@label`, and captures `(heredoc_body)` as `@string`.
- `runtime/queries/bash/injections.scm` uses the parser-produced `(heredoc_body)` as `@injection.content` and the parser-produced `(heredoc_end)` as `@injection.language`.
- `lua/nvim-treesitter/parsers.lua` pins Bash to `tree-sitter/tree-sitter-bash` revision `a06c2e4415e9bc0346c6b86d401879ffb44058f7`.
- That Bash grammar uses an external scanner in `src/scanner.c` to recognise heredoc start/body/end tokens. Its heredoc scanner maintains delimiter state and returns `HEREDOC_END` when the current line matches the active delimiter.

This establishes that the standard Bash injection query consumes the Bash parser's own heredoc boundary; it does not consume the nvim-heredoc plugin's scanner-derived body range. It also establishes that the heredoc terminator capture is a standard Bash highlight. It does **not** yet establish why the target buffer's inner `EOF` is being captured or whether the outer parse is actually truncated: that requires the exact minimal buffer and its parse tree from the target Neovim installation. Do not change the upstream grammar, query, or plugin integration based on this source inspection alone.

## Future development direction (not current task work)

When this area is deliberately reopened, investigate syntax presentation as part of a broader embedded-language capability rather than limiting the design to Bash heredoc body highlighting. Tree-sitter injections are one possible mechanism for presenting embedded content such as Python, Rust, markup, and other payload languages. The investigation may need to establish parser-tree boundaries, injection content ranges, language selection, unknown-language fallback, and lifecycle behaviour.

That future work must consume the plugin's authoritative scanner-established region; it must not make Tree-sitter the source of truth for heredoc structure or introduce a Tree-sitter dependency into closer insertion or payload editing. Injection should not be assumed to solve the containing-parser boundary, language services, diagnostics, completion, linting, or formatting without separate evidence.

The exact parser revisions, parse-tree node ranges, query captures, supported APIs, injection strategy, and language-classification model are intentionally left for that future investigation. No such diagnosis is requested or implied by this task's current status.

## Implementation constraints

- Do not change the scanner's Return-local scope-establishment contract.
- Do not make Tree-sitter a dependency for closer insertion or payload editing.
- Do not use the Bash parser as the source of the payload boundary.
- Do not treat a highlight query that merely recolours the inner `EOF` as sufficient if the containing parser still adopts it as an outer-shell terminator.
- Do not assume an injection is sufficient without proving that the containing shell parse no longer claims the payload.
- Do not hard-code `EOF` or rely on matching delimiter names; use the scanner-established region.
- Do not assume all payloads are Bash. Unknown payloads must remain opaque rather than being parsed as shell by default.
- Do not introduce buffer-wide disabling of Tree-sitter or other editor tooling as a substitute for region containment.
- Do not modify the user's private Neovim configuration. Any integration must be opt-in or provided by a documented plugin-owned interface, with no global parser/query side effects.
- Preserve normal shell parsing/highlighting before and after the payload region.
- Keep this task focused on syntax representation. Diagnostics, completion, LSP, linting, and formatter isolation remain separate integrations unless a concrete dependency is demonstrated.

## Existing CI coverage and diagnostic gap

The repository's existing `.github/workflows/test.yml` runs five independent jobs:

- `core`: Lua scanner tests, with `shfmt --to-json` used as an mvdan/sh syntax oracle for selected unsupported-grammar fixtures.
- `buffer-integration`: headless Neovim editing and changed-range tests.
- `shell-delivery`: Bash, Dash, and Zsh payload-byte comparisons.
- `formatter`: `shfmt -i 0 -p` payload-preservation checks.
- `lazyvim-integration`: pinned Neovim/LazyVim/plugin coexistence tests.

These are useful regression layers, but the current workflow does **not** install or pin nvim-treesitter or the Bash Tree-sitter parser, and it does not inspect parser trees or query captures. The `shfmt --to-json` step is an independent shell-syntax oracle; it is not a Tree-sitter test. A green result from the existing five jobs therefore cannot establish syntax-presentation containment.

The non-colliding cargo fixture is added at `tests/fixtures/heredoc-cargo-distinct-delimiters.sh` and is consumed by:
- the Lua scanner suite, to assert that the embedded opener/terminator remain payload and that the outer `EOF` alone closes the scanner's outer region;
- shell-delivery tests, to compare the exact bytes delivered by Bash, Dash, and Zsh when available;
- formatter tests, to check that `shfmt` does not change the delivered cargo payload.

The existing same-delimiter scanner regression remains a separate collision case. The existing live Neovim payload tests remain editing-behaviour tests; they do not inspect Tree-sitter highlighting.

The existing CI gap is recorded for future reference only. Adding a Tree-sitter parser environment or parser-tree diagnostic is not the next action for this task and is not required to validate the current scanner, shell-delivery, or formatter regressions.

## Current regression evidence (2026-11-19)

Hosted workflow run [44640744894](https://github.com/incus-skills/nvim-heredoc/actions/runs/44640744894) completed with all five jobs successful:

- `core scanner` — passed.
- `Neovim buffer integration` — passed.
- `shell delivery` — passed.
- `shfmt payload preservation` — passed.
- `LazyVim plugin coexistence` — passed.

This confirms the current CI regression layers for scanner recognition, editing behaviour, shell-delivered payload bytes, formatter preservation, and plugin coexistence. It does not establish Tree-sitter syntax-presentation containment: the workflow does not install or test the pinned nvim-treesitter/Bash parser tree or query captures. That distinction is intentional; parser-tree and injection work is deferred as described above.

## Regression fixture already added

The distinct-delimiter fixture and its scanner, shell-delivery, and formatter checks have already been added. Their current purpose is to establish all of the following:

1. The outer opener and its actual terminator define one complete payload region.
2. In the non-colliding fixture, the inner heredoc opener and its distinct terminator remain inside the outer payload region and are not represented as active constructs/terminators of the containing Bash document.
3. In the non-colliding fixture, the outer terminator remains the only boundary that closes the containing heredoc. The collision fixture separately records Bash's first-matching-delimiter behaviour and must not be assigned the same expected shell-delivery range.
4. Shell syntax immediately following the outer terminator is parsed/highlighted as shell syntax.
5. An unknown payload remains opaque; no fallback to Bash parsing is silently applied.
6. Edits before, within, and after the body update the represented range without stale offsets or leakage.
7. Incomplete opener/body/terminator states fail conservatively and do not let the parser claim uncertain payload as active shell syntax.
8. Existing live heredoc payload Return tests continue to pass unchanged.
9. The solution leaves ordinary shell regions outside the payload with their existing parser/highlighting behaviour.

## Current-task acceptance / handoff boundary

- Preserve the distinct-delimiter fixture as the primary non-colliding cargo fixture.
- Keep the same-delimiter shell collision separate and explain it using Bash `<<-` matching semantics.
- Keep scanner-derived region assertions distinct from shell-delivery assertions and from syntax-presentation claims.
- Report the actual results of scanner, editing, shell-delivery, formatter, and plugin-coexistence tests without claiming they prove Tree-sitter containment.
- Report hosted CI evidence and live workstation verification separately.
- Do not add parser-tree diagnosis, injection implementation, or syntax-presentation changes to this task.

## Handoff

Report:

1. Minimal reproducer and observed parser tree/captures.
2. Exact Neovim, nvim-treesitter, and Bash parser revisions inspected.
3. Root cause: grammar/external scanner, query, or both.
4. Candidate mechanisms considered and why they do or do not satisfy containment.
5. Chosen presentation mechanism and its verified API/lifecycle.
6. Files changed and any new public configuration/interface.
7. Regression tests and exact results.
8. Known parser/filetype limitations.
9. Whether the current inner-`EOF` mismatch is fully resolved or only masked.
10. Recommended next task for other embedded-language integrations.

Keep this record as deferred future-development context. Reopen it only when a broader embedded-language presentation investigation is explicitly authorised; do not continue parser-tree diagnosis as an implied next step.
