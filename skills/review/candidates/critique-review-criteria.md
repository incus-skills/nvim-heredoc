# Candidate: Critique of review criteria

**Status:** Candidate; emerging from evaluation of `maxgoff/unslop`.

## Origin

The project selected `maxgoff/unslop` as one noncanonical approach for critiquing AI-influenced code and project practices. Its emphasis on reducing unearned abstraction, boilerplate, unnecessary documentation, and prescriptive patterns is useful, but mechanical application could remove context, collapse meaningful distinctions, or replace uncertainty with artificial certainty.

The critique therefore became part of the review rather than merely a rubric applied to the repository.

## Purpose

Examine a review framework or criterion as an influence on the observer's interpretation. Identify what it makes visible, what it obscures, which assumptions it imports, and what distortions may result from applying it without context.

## Useful distinctions

- A criterion is a lens, not a verdict.
- A useful heuristic is not necessarily a universal rule.
- Reducing unnecessary complexity is different from reducing all complexity.
- Concision is different from reconstructability.
- Consistency is different from preserving meaning.
- A criterion can expose one failure mode while introducing another.

## Questions to explore

- What problem was this criterion designed to address?
- Which project characteristics does it assume?
- What does it make easier to notice?
- What relevant capability, evidence, or context might it cause the reviewer to overlook?
- What happens if it is applied mechanically?
- Does it preserve or constrain capabilities the project may need?
- What parts are useful in this context, and what should remain inapplicable or unresolved?

## Application notes

The current `unslop` review distinguishes high-value concerns such as unearned abstraction and unnecessary defensive machinery from lower-value surface heuristics such as banned vocabulary or punctuation patterns. It also recognises that conservative handling of ambiguous syntax, repeated documentation entry points, and substantial design context may have project-specific value.

The criteria should be assessed in relation to the actual code, architecture, documentation, and workflow rather than assigned a universal score.

## Risks and limits

- Do not replace one prescriptive rubric with another.
- Do not treat all external criteria as equally relevant.
- Do not reject a criterion merely because it is imperfect; examine its useful scope and failure modes.
- Do not allow critique of the rubric to distract from concrete evidence about the review subject.

## Open questions

- How can useful criteria be combined without creating a rigid composite checklist?
- What forms of evidence help identify distortions introduced by a review lens?
- How should conflicting but individually useful criteria be handled in different project contexts?
