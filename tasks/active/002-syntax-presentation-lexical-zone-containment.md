# Task 002 — Enforce lexical-zone boundaries in syntax representation

**Status:** active — policy adopted; implementation investigation not started  
**Priority:** high — current syntax representation contradicts the adopted design contract  
**Scope:** determine and implement a syntax-presentation path that prevents the containing shell parser from claiming established heredoc payload as active shell syntax. Do not change the Return-local editing architecture or select a payload-language strategy by assumption.

## Governing policy

The adopted policy is recorded in [the design contract](../../docs/design.md) and [future development context](../../docs/future-development-context.md):

- An established heredoc body is a lexical zone distinct from the active syntax of its containing shell document.
- The boundary is authoritative for both editing behaviour and syntax representation.
- The containing shell parse must not adopt an inner payload heredoc delimiter (including an inner `EOF`) as an outer-shell heredoc terminator or construct.
- Payload classification is independent of structural recognition. An unknown payload must not silently become active Bash syntax.
- The visual representation may eventually be a contained-language parse/injection or opaque content. The project has not selected that strategy.
- The existing scanner/closer boundary is the structural source of truth. A syntax parser or injection query must not independently redefine it.

**Defer how the payload is represented, not whether its lexical boundary is respected.**

## Objective

Resolve the observed mismatch in which the installed Tree-sitter Bash parser highlights/adopts an inner heredoc `EOF` as Bash syntax inside an already-established outer payload region. Ensure the containing shell parse does not claim that payload content as active shell syntax, while allowing ordinary shell syntax after the outer terminator to be represented normally.

The first implementation target is the reproduced Bash case. Do not claim equivalent behaviour for POSIX sh or Zsh until their parsers and fixtures are independently assessed.

## Initial source inspection

The pinned nvim-treesitter revision recorded in the project compatibility inventory is `19bdfc04f40ed2ccb3340591d125f759b0406875`. At that revision:

- `runtime/queries/bash/highlights.scm` captures both `(heredoc_start)` and `(heredoc_end)` as `@label`, and captures `(heredoc_body)` as `@string`.
- `runtime/queries/bash/injections.scm` uses the parser-produced `(heredoc_body)` as `@injection.content` and the parser-produced `(heredoc_end)` as `@injection.language`.
- `lua/nvim-treesitter/parsers.lua` pins Bash to `tree-sitter/tree-sitter-bash` revision `a06c2e4415e9bc0346c6b86d401879ffb44058f7`.
- That Bash grammar uses an external scanner in `src/scanner.c` to recognise heredoc start/body/end tokens. Its heredoc scanner maintains delimiter state and returns `HEREDOC_END` when the current line matches the active delimiter.

This establishes that the standard Bash injection query consumes the Bash parser's own heredoc boundary; it does not consume the nvim-heredoc plugin's scanner-derived body range. It also establishes that the heredoc terminator capture is a standard Bash highlight. It does **not** yet establish why the target buffer's inner `EOF` is being captured or whether the outer parse is actually truncated: that requires the exact minimal buffer and its parse tree from the target Neovim installation. Do not change the upstream grammar, query, or plugin integration based on this source inspection alone.

## Required investigation

1. Reproduce the exact current behaviour with a minimal fixture containing an outer heredoc, embedded script text with an inner heredoc opener and `EOF` terminator, and shell syntax after the outer terminator. Record the exact outer and inner delimiters; distinguish a parser capture on the inner line from an actual truncation/misparse of the outer heredoc body.
2. Inspect the exact installed Neovim, nvim-treesitter, and Bash parser revisions used by the target environment. Identify which parser nodes/captures cover the outer opener, body, inner opener, inner `EOF`, outer terminator, and following shell code.
3. Establish whether the current parser's behaviour is caused by the Bash grammar/external scanner, highlight query captures, or both. Do not infer parse structure from `:Inspect` captures alone.
4. Inspect supported Neovim Tree-sitter APIs for representing scanner-derived included regions or contained-language regions. Verify actual APIs at the pinned target revision; do not rely on undocumented or guessed methods.
5. Evaluate candidate mechanisms against the adopted policy:
   - scanner-derived region/included-range handling;
   - a contained-language injection whose range is derived from the authoritative body boundary;
   - a parser/grammar change where the current Bash parser cannot represent the required boundary;
   - an opaque presentation fallback when no safe contained-language representation is available.
6. Determine whether a mechanism can stop the containing Bash parse from claiming the payload, rather than merely overlaying another highlight on top of an already incorrect outer parse.
7. Identify ownership and lifecycle: who updates the presentation range after edits, how incomplete buffers behave, and how parser refreshes avoid stale or overlapping regions.
8. Keep language classification separate. A successful structural boundary must work even when the payload language is unknown. Shebang and receiving-command signals remain possible future classification evidence, not prerequisites for boundary correctness.

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

## Required regression fixture

Create a minimal fixture and tests that establish all of the following:

1. The outer opener and its actual terminator define one complete payload region.
2. An inner heredoc opener and inner `EOF` line remain inside that region and are not represented as active constructs/terminators of the containing Bash document.
3. The outer terminator remains the only boundary that closes the containing heredoc.
4. Shell syntax immediately following the outer terminator is parsed/highlighted as shell syntax.
5. An unknown payload remains opaque; no fallback to Bash parsing is silently applied.
6. Edits before, within, and after the body update the represented range without stale offsets or leakage.
7. Incomplete opener/body/terminator states fail conservatively and do not let the parser claim uncertain payload as active shell syntax.
8. Existing live heredoc payload Return tests continue to pass unchanged.
9. The solution leaves ordinary shell regions outside the payload with their existing parser/highlighting behaviour.

## Acceptance criteria

- The exact current Tree-sitter Bash mismatch is reproduced and explained from parser structure and query behaviour.
- The chosen mechanism is supported by verified APIs at the pinned target revision.
- The containing Bash parse no longer treats inner payload heredoc syntax as active shell syntax.
- The outer body boundary comes from the plugin's established lexical region, not a second delimiter-matching implementation.
- Unknown payloads are opaque.
- Shell parsing resumes correctly after the outer terminator.
- Region updates are safe across edits and incomplete buffers.
- Existing editing, scanner, shell-delivery, formatter, and plugin-coexistence regressions remain green.
- Hosted CI evidence and live workstation verification are reported separately.

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

Keep this task in `active/` until implementation, regression tests, and handoff are complete.
