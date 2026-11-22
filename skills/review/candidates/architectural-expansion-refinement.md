# Candidate: Architectural expansion and refinement

**Status:** Candidate; emerging from the current `nvim-heredoc` review.

## Origin

The project moved from a document-wide heredoc discovery and tracking model to a Return-local model in which pressing Return after a completed managed opener commits the closer and establishes the body boundary.

The implementation may have retained responsibilities inherited from the earlier architecture. At the same time, the scanner's structural decomposition may contain capabilities useful to future syntax presentation, including possible toggleable Tree-sitter injection for heredoc body or lexical-zone highlighting.

This exposed the need to review an architectural pivot as a discontinuity, while preserving useful discoveries from the earlier expansion phase.

## Purpose

Help an observer reassess an implementation after a meaningful architectural change without assuming either that inherited responsibilities remain necessary or that everything not needed by the immediate operation should be discarded.

## Useful distinctions

- **Distinction:** structural knowledge or a relationship made visible during exploration.
- **Capability:** what the system can recognise, represent, or do using that distinction.
- **Mechanism:** the current code or process that realises the capability.
- **Responsibility:** the operation or consumer that currently depends on the mechanism.

A change in responsibility does not by itself invalidate a distinction. Removing or replacing a mechanism need not mean losing the capability. A potential future consumer may matter to the capability assessment without justifying unnecessary current complexity.

## Questions to explore

- What changed in the architecture, and which former assumptions no longer hold?
- Which responsibilities were introduced to serve the earlier model?
- What does the current operational model actually require?
- Which structural distinctions remain useful independently of their original consumers?
- Could a credible future consumer need those distinctions?
- Can the capability be retained with a narrower or differently placed mechanism?
- What evidence would distinguish an obsolete responsibility from a reusable capability?

For `nvim-heredoc`, this includes examining scanner and integration responsibilities together, and considering future syntax-presentation needs without treating Tree-sitter injection as a current implementation requirement.

## Risks and limits

- Do not presume every old mechanism is obsolete merely because the architecture changed.
- Do not preserve a mechanism wholesale merely because it contains useful structural knowledge.
- Do not let speculative future features justify current complexity without examining the capability/mechanism distinction.
- Do not turn the audit into a subtractive code-minimisation exercise.

## Application and refinement

Initial application: the Return-local architectural review of `nvim-heredoc`.

Further applications should record where the distinction between responsibility, mechanism, and capability transfers cleanly, where it needs adaptation, and where it obscures a different kind of architectural change.

## Open questions

- What evidence is sufficient to distinguish a reusable structural capability from accidental implementation detail?
- How should future consumers influence present decomposition when their interfaces are not yet designed?
- Which parts of this practice apply to non-code systems or projects without a clear architectural pivot?
