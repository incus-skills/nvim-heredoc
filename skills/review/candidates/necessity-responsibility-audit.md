# Candidate: Necessity and responsibility audit

**Status:** Candidate; emerging from the current `nvim-heredoc` review.

## Origin

The Return-local pivot may have removed the need for parts of the earlier document-wide model: broad lexical discovery, multiple-heredoc tracking, full-buffer scans, snapshots, transition reconciliation, and recovery for changes elsewhere in a document. Their continued operation or passing tests do not establish that these responsibilities remain necessary.

## Purpose

Evaluate mechanisms against the current architecture by tracing them to actual consumers, observable behaviour, requirements, and failure conditions.

## Useful distinctions

- A mechanism can work correctly in tested scenarios without being necessary to the current architecture.
- A test can preserve historical behaviour without proving that the behaviour remains required.
- A mechanism can impose maintenance, state, coupling, or execution costs even when it causes no immediate functional harm.
- A mechanism may support a reusable capability even if its original operational responsibility has disappeared.

## Questions to explore

- Which current operation consumes this mechanism?
- What concrete behaviour or failure does it address?
- Is that behaviour part of the current contract?
- Does the test demonstrate a requirement, or merely encode an earlier implementation model?
- What state, complexity, execution cost, or coupling does the mechanism introduce?
- Would narrowing or relocating it preserve the needed capability?
- What evidence is missing before a conclusion can be drawn?

## Application notes

For the current scanner and integration review, candidate areas include:

- Full-buffer scans and their consumers.
- Broad shell lexical recognition versus local opener and payload-boundary recognition.
- Multiple-heredoc queues and their relevance to Return-local editing.
- Scanner snapshots and deferred range processing.
- Managed-operator transition reconciliation.
- Recovery loops and the concrete state they recover.
- Tests whose expectations may have originated in the earlier architecture.

These are audit targets, not predetermined removals.

## Risks and limits

- Do not equate smaller code with better architecture.
- Do not remove tests solely because their original rationale is unclear; investigate what behaviour they currently establish.
- Do not mistake absence of a known consumer for proof that a capability has no value.
- Do not infer necessity from test success alone, or obsolescence from architectural change alone.

## Open questions

- How should indirect consumers and externally observable behaviour be represented?
- When is maintenance burden sufficient reason to replace a working mechanism?
- How can test suites distinguish contract tests from historical implementation tests without losing useful regression coverage?
