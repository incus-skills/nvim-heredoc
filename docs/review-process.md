# Review process

## Purpose

This document records a review practice that is emerging from the project's pre-release and architectural reviews. It is intended to support this review and subsequent review cycles, including reviews that use external critique approaches such as `unslop`.

The process is an aid to observation and reasoning, not a fixed rubric or a procedure that predetermines outcomes. The review subject, its current architecture, the available evidence, and the review criteria all remain open to examination.

The project-level objective is reconstructability: a new contributor or AI session should be able to enter the project, understand the relevant history and current state, and exercise independent judgement. Documentation should enable that reasoning rather than prescribe every interpretation.

## Review as an iterative capability

A review cycle can produce more than findings about the current implementation. It can expose reusable distinctions, methods, and capabilities that may be useful in later reviews or other projects.

The project therefore maintains a review-skills collection in [`skills/review/`](../skills/review/README.md). It is a working space for collecting candidate skills, recording their project applications, and refining them as further evidence appears.

The collection is not a claim that every observed practice is universally transferable. A candidate becomes more reusable through application in different contexts, where its assumptions, limits, and adaptations can be observed.

## Review perspectives

The following perspectives have emerged from the current review. They can overlap and need not be applied as a rigid sequence.

### Architectural expansion and refinement

Treat a meaningful architectural pivot as a possible discontinuity. Re-evaluate responsibilities against the current model rather than assuming that responsibilities inherited from an earlier design remain legitimate.

At the same time, do not reduce refinement to subtraction. Preserve useful structural distinctions and decomposition discovered during earlier widening. Distinguish:

- **Distinction:** the structural knowledge or relationship that has been made visible.
- **Capability:** what the system can recognise, represent, or do because of that distinction.
- **Mechanism:** the present implementation that realises the capability.
- **Responsibility:** the operation or consumer that currently depends on the mechanism.

A responsibility can become obsolete without invalidating the distinction or capability. A mechanism can be replaced without discarding the knowledge it embodies. Conversely, a possible future consumer should inform the assessment of a capability without automatically justifying all of its current implementation.

For this project, Return-local scope creation is the current operational model. The scanner should be assessed against that model while retaining awareness of its possible future role in syntax presentation, including toggleable Tree-sitter injection of heredoc payload or lexical zones. That future direction is context for evaluating reusable structural information, not a commitment to implement injection as part of the current review.

### Necessity, responsibility, and evidence

Trace mechanisms to actual consumers, observable behaviour, requirements, or failure conditions. Ask whether the current architecture still needs the responsibility, not merely whether the existing code performs it correctly.

Passing tests demonstrate behaviour for the tested cases; they do not independently demonstrate that a mechanism is architecturally necessary. Tests may encode historical behaviour or preserve assumptions from an earlier design. Treat that as a question to investigate, not as grounds to discard tests automatically.

For each substantial mechanism, record what is established, what is hypothesised, and what remains unresolved. Consider implementation burden, coupling, state, execution cost, and the cost of losing a reusable capability. Possible outcomes include retaining, narrowing, relocating, replacing, removing, or leaving the question open. These are descriptive possibilities, not required labels or a mandatory decision set.

### Critique of the review criteria

External rubrics and review approaches are themselves material for review. Examine what each criterion makes visible, what it obscures, the assumptions it imports, and the failure modes that may arise if it is applied mechanically.

A criterion intended to reduce unnecessary complexity can also remove useful decomposition. A preference for concise documentation can remove context needed for independent reasoning. A demand for consistency can flatten distinctions or turn unresolved questions into artificial certainty.

Ask whether a criterion helps distinguish unnecessary implementation from necessary capability, and whether it preserves or constrains capabilities the project may need. Do not treat any external approach as canonical merely because it is useful.

### Reconstructability

Evaluate documentation and workflow by whether they allow a new observer to reconstruct the project sufficiently to reason about it.

Preserve relevant decisions, rationale, evidence, provenance, current state, alternatives, and unresolved questions. Prune genuinely redundant information, but do not assume that every recurrence is duplication: material may serve different entry points or interpretive purposes.

Avoid turning project documentation into an exhaustive set of instructions that dictates conclusions. Code contracts need precise, testable behaviour; project documentation needs to preserve enough context for informed interpretation and judgement.

## Capturing learning during a review

When a review exposes a potentially reusable practice:

1. Record the observation in the skills collection as a candidate, with the project context that gave rise to it.
2. Describe the capability the practice offers, rather than immediately turning it into a universal rule.
3. Preserve the evidence, assumptions, limitations, and unresolved questions that currently bound it.
4. Link the candidate to the review or project material that demonstrates its application.
5. Revisit it during later reviews. Record adaptations, counterexamples, and differences between contexts rather than forcing uniformity.
6. Refine, combine, separate, defer, or retire candidates as the accumulated experience warrants.

Not every observation needs to become a skill. The collection should remain useful rather than become an inventory of every review note.

## Scope and evidence boundaries

A review should state what it examines and what it does not. Distinguish repository inspection from local execution, hosted CI results from workstation validation, and observed behaviour from inferred design intent.

Unless a review explicitly includes implementation work, findings and proposals do not authorise code changes. Keep observations, interpretations, hypotheses, and proposed changes distinguishable.

## Current review context

The current review examines the implementation and documentation against the Return-local architecture, while also evaluating the criteria supplied by `maxgoff/unslop` as one noncanonical critique approach. The scanner and integration layer are considered together because their responsibilities were shaped by the earlier document-wide model.

The initial skill candidates in [`skills/review/candidates/`](../skills/review/README.md) emerged from this review. They are provisional and should be tested and refined in subsequent cycles.
