# Pre-release field validation

## Purpose

The core heredoc editing and autoformatting objective has, in large part, been achieved. This pre-release is intended to make the current implementation available as a stable, identifiable baseline for field testing in real LazyVim configurations.

The purpose of field testing is to discover:

- Functional edge cases not represented by the current fixtures.
- Differences caused by real Neovim, LazyVim, shell, formatter, and plugin configurations.
- Runtime reliability and efficiency problems.
- Unnecessary complexity and opportunities to simplify the implementation without regressing observable behaviour.

Field findings should be recorded with a reproducible example, expected editing behaviour, observed result, environment/version details, and whether shell-delivered bytes were affected. Prioritise correctness and usability defects before speculative capability expansion.

## What this pre-release is testing

The existing core behaviour is the subject of field validation:

- Automatic matching-closer insertion after a completed managed `<<-` opener.
- Structural placement and indentation of the opener and closer.
- Predictable body editing and preservation of relative indentation and pasted content.
- Conservative handling of ambiguous or unsupported syntax.
- Non-interference with ordinary `<<` heredocs and `<<<` here-strings.
- Coexistence with the user's existing LazyVim indentation, completion, pair insertion, and formatting setup.
- Shell-delivery and formatter behaviour for the tested cases.

The current CI workflow exercises five layers independently: core scanner, Neovim buffer integration, shell delivery, formatter payload preservation, and pinned LazyVim/plugin coexistence. The latest main-branch run before this field-validation documentation, [run 44651280055](https://github.com/incus-skills/nvim-heredoc/actions/runs/44651280055), passed all five jobs. This is hosted test evidence, not a substitute for live workstation or field testing.

## Not part of the pre-release acceptance scope

The following are stretch goals and must not delay field validation of the core editing behaviour:

- **Nested heredoc indentation:** Bash's native `<<-` processing strips all leading TAB bytes from each line of the current heredoc body. It does not maintain nested indentation levels for a later inner heredoc. Any editor representation that preserves nested indentation across successive shell-delivery stages is an extension beyond that native metaphor and requires a separate design and test.
- **Embedded-language presentation:** recognising and presenting heredoc payloads as embedded languages, potentially through Tree-sitter injection or another mechanism, is a separate semantic/presentation extension. It is not required to establish the core editing and autoformatting objective.

These are valid future investigations, not missing prerequisites for the pre-release.

## Known qualification

The pre-release is a field-testing baseline, not a claim of complete shell grammar coverage or universal compatibility. The scanner is intentionally bounded. The current task records remaining live-workstation verification and architectural simplification work. Do not generalise fixture-specific formatter or shell-delivery results beyond the cases and versions actually exercised.

## Field report template

For each finding, record:

1. Minimal source fixture and exact reproduction steps.
2. Expected editing/formatting behaviour.
3. Actual behaviour and whether it is repeatable.
4. Neovim, LazyVim, shell, formatter, and relevant plugin versions.
5. Whether the buffer text changed unexpectedly.
6. Whether shell-delivered payload bytes changed.
7. Impact: correctness, usability, compatibility, efficiency, or maintainability.
8. Suggested correction, if known; keep observation separate from proposed implementation.

The guiding question for prioritisation is whether the finding improves the reliability, predictability, efficiency, or simplicity of the existing heredoc editing experience.
