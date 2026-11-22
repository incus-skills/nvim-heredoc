# Candidate: Reconstructability review

**Status:** Candidate; emerging from the current project review.

## Origin

The review identified that documentation and workflow serve as ingress surfaces for new observers, including AI sessions operating without the originating conversation. Their purpose is not only to state current rules, but to preserve enough context for independent reconstruction and reasoning.

This complicates conventional advice to consolidate repeated material: some recurrence may serve different interpretive entry points, while genuine duplication can still create drift and unnecessary maintenance.

## Purpose

Assess whether project documentation and workflow preserve sufficient context for a new observer to understand the project's current state, relevant history, evidence, decisions, and unresolved questions without dictating every conclusion.

## Useful distinctions

- **Code-level determinism:** implementation behaviour, contracts, boundaries, and failure conditions should be precise enough to test.
- **Project-level reconstructability:** documentation and workflow should preserve the context needed to understand and reason about the project.
- **Repetition:** recurring material may be redundant, or it may serve a different entry point or interpretive purpose.
- **Uncertainty:** unresolved questions and alternatives may be essential project state rather than documentation defects.

## Questions to explore

- Can a new observer identify the current objective, architecture, and project state?
- Can they reconstruct why important decisions were made and what evidence informed them?
- Are assumptions, alternatives, limitations, and unresolved questions visible?
- Does the documentation distinguish established facts from proposals and hypotheses?
- Is repeated information genuinely redundant, or does it support a distinct entry point?
- Does workflow help an observer recover context without forcing a predetermined interpretation?
- What context would be lost if a document were shortened or consolidated?

## Application notes

For `nvim-heredoc`, this includes reviewing the README, design contract, pre-release field-validation material, task records, and future-development context as an ingress ecology. The goal is not to make all documents identical or to impose a single canonical formulation where different views serve different purposes.

## Risks and limits

- Do not preserve every historical detail regardless of relevance.
- Do not assume every repeated statement is useful.
- Do not optimise for a first-time reader at the expense of the information needed by a returning contributor.
- Do not turn documentation into an exhaustive instruction set that substitutes for judgement.

## Open questions

- Which forms of provenance and decision history are most important for different kinds of projects?
- How can documentation support multiple entry points without creating confusing contradictions?
- What evidence indicates that a new observer can reconstruct the project rather than merely repeat its current rules?
