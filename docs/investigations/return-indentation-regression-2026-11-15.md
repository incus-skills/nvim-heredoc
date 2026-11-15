# Return indentation regression investigation

**Date:** 2026-11-15  
**Status:** Resolved for the tested interactive Return path; historical trigger not isolated  
**Implementation reference:** `deaf7077b1f74c0a3b683121fcbc59d0d1d71105`  
**Historical working reference:** annotated tag `working-baseline` at `35889cfb90963ba0c6ef8b91570b65328c30bbea`

## Summary

The reported regression was that the first line of an indented `<<-` heredoc body received the expected structural indentation, but subsequent Return operations accumulated additional indentation. The investigation now has a reproducible regression trace and a passing control with the active shell indent expression retained.

The repaired implementation passes the tested Return sequence in the user's Neovim 0.12.4 LazyVim environment, with MiniPairs active, `GetShIndent()` active, and `expandtab=true`. The final body and closer lines contain the expected literal TAB bytes, without accumulating spaces.

This establishes a functional fix for the exercised path. It does not establish that every shell grammar, editor configuration, or plugin combination is supported, nor does it isolate one historical commit as the sole causal correction.

## Original symptom and test shape

The minimal case is a `<<-` heredoc nested in a shell function, with a two-space-indented opener:

```bash
conf_print_test() {
  cat <<-'TRACE'
```

The opener's original bytes must remain unchanged. With the tested `tabstop=2` configuration, the expected body prefix is two literal TAB bytes and the expected closer prefix is one literal TAB byte. Each body line must receive exactly that body prefix once.

The original local trace showed the first body line correctly indented, while later Return operations introduced additional spaces. Both native Return and the MiniPairs Return path were investigated. Disabling `indentexpr` did not initially make the original failing trace pass, so the issue was not attributed solely to the shell indent expression.

## Changes made during the investigation

The implementation and test harness evolved through several targeted corrections:

- Reconcile the complete buffer after relevant edits rather than relying only on the reported changed-line range.
- Replace Neovim-generated indentation on an interactive blank body line as a whole, rather than adding a structural prefix while leaving generated whitespace behind.
- Restrict the autoindent normalisation to live interactive edits; do not apply that conversion to paste ranges, where whitespace may be intentional payload.
- Keep the user's `expandtab`, `tabstop`, `softtabstop`, and `shiftwidth` settings under user configuration control. The plugin inserts literal TAB bytes where `<<-` requires them and does not impose editor indentation options.
- Remove an invalid synchronous native-Return diagnostic from the harness after it was shown to leave Insert mode and produce a test-harness failure unrelated to indentation.
- Extend `scripts/trace-return.lua` so it can run both as an `indentexpr`-disabled control and with the active shell `indentexpr` retained, selected by `NVIM_HEREDOC_KEEP_INDENTEXPR=1`.

These are the changes made during the investigation, not a claim that each item independently caused or fixed the original symptom.

## Local verification

Two final traces were supplied from the user's actual Neovim 0.12.4 LazyVim environment.

### Disabled-indentexpr control

- Filetype: `sh`; plugin attached.
- `expandtab=true`, `tabstop=2`, `softtabstop=0`, `shiftwidth=2`.
- `autoindent=true`; shell `indentexpr` disabled only in the scratch buffer.
- MiniPairs Return mapping active.
- Body lines contained exactly two leading literal TAB bytes.
- Closing delimiter contained exactly one leading literal TAB byte.
- No accumulating spaces; trace result: `PASS`.

### Active-indentexpr integration

- Same Neovim, filetype, plugin, indentation options, and MiniPairs mapping.
- Shell `indentexpr=GetShIndent()` retained and active in the scratch buffer.
- Each Return-generated blank body line contained exactly two literal TAB bytes.
- Final body lines contained exactly two leading literal TAB bytes; closer contained exactly one.
- No accumulating whitespace; cursor position was as expected; trace result: `PASS`.

The active-indentexpr trace is the decisive local integration check: it exercises the interaction that the earlier disabled-indentexpr control did not.

## CI verification

GitHub Actions run [43672894832](https://github.com/incus-skills/nvim-heredoc/actions/runs/43672894832) completed successfully. All five jobs passed:

- Core scanner
- Neovim buffer integration
- Shell delivery
- shfmt payload preservation
- LazyVim plugin coexistence

The LazyVim integration job uses the pinned Neovim 0.12.4 fixture and exercises MiniPairs with the active shell indent expression. The run's five successful jobs are recorded separately from the local workstation traces: CI validates the controlled fixture; the local traces validate the user's actual environment.

## Causal uncertainty and limits

The exact historical trigger has not been isolated through a controlled revert or bisect. The observed resolution followed multiple implementation and harness corrections, so it would be inaccurate to identify one change as the definitive root cause.

The verification covers the reported indented Return workflow and the stated integration combination. It is not a completion claim for the repository's broader active Task 001, scanner grammar limits, all paste/edit sequences, every supported shell, or every Neovim distribution and plugin configuration.

## Functional status and tagging guidance

The Return-indentation regression can be treated as resolved for the tested configuration. The implementation at the reference commit is a reasonable candidate for a new functional tag, provided the tag is explicitly understood as a tested functional checkpoint rather than a claim that all broader project work is complete.

The existing `working-baseline` tag is the historical known-good arrangement and must remain unchanged. A new tag should point to the verified repaired commit (or a later documentation-only commit that preserves that exact implementation), and should have an annotated message describing the functional scope. Do not move or rewrite the historical tag.
