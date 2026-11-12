# Task 001 — Core design and executable prototype

**Status:** active  
**Priority:** foundational  
**Scope:** establish and test the shared lexical model for managed `<<-` heredocs. Do not produce a user-facing installer yet.

## Objective

Build a conservative scanner/prototype that can identify managed `<<-` heredoc regions in Bash, POSIX `sh`, and Zsh source without requiring Treesitter. Use the same scanner for all three; Treesitter may be an optional later optimisation.

## Required work

1. Inspect the repository state and establish the implementation/test layout.
2. Define a scanner interface that returns opener, delimiter, body range, queue ordering, and ambiguity information.
3. Implement operator recognition that ignores quoted/escaped contexts and comments, distinguishes `<<-`, `<<`, and `<<<`, and handles quoted/escaped delimiters.
4. Model multiple pending heredocs on a command in declaration order, including command continuation before body consumption.
5. Make malformed or ambiguous input fail conservatively without modifying source.
6. Add buffer-independent unit tests for scanner results.
7. Add shell-delivery fixtures that demonstrate actual `<<-` tab stripping and payload bytes.
8. Record unresolved grammar limits explicitly rather than claiming complete shell parsing.

## Acceptance criteria

- Ordinary `<<` and `<<<` are never classified as managed heredocs.
- Operators inside quotes, escaped text, and comments are not detected as heredoc openers.
- Multiple heredocs are associated with their correct body blocks in declaration order.
- Quoted delimiters are matched correctly while preserving source spelling.
- Leading tabs and leading spaces are treated distinctly.
- The tests demonstrate what Bash, POSIX `sh`, and Zsh actually receive where those shells are available.
- The scanner does not depend on Treesitter being installed.
- Test output is reproducible with documented commands.

## Boundaries

- Do not change the user's Neovim configuration.
- Do not implement auto-pair/completion suppression until the actual installed plugin APIs have been inspected.
- Do not add Zsh to `shfmt` formatting.
- Do not strip or normalise pasted body whitespace.
- Do not write an installer in this task.

## Handoff

When complete, report:
1. Files added/changed.
2. Scanner model and known limits.
3. Tests run and exact results.
4. Shells available and tested.
5. Unresolved cases.
6. Recommended next task.

Keep this task in `active/` until implementation, tests, and handoff are complete.
