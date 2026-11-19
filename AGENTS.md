# Repository collaboration and ingress

## Session ingress

A new session must reconstruct the current working position from repository evidence rather than assume that prior conversation context is available.

Before making changes:

1. Read this file and [the collaboration model](docs/collaboration-model.md).
2. Read the relevant technical contract and current project documentation for the area being touched.
3. Inspect the active task or issue governing the work, if one exists, and follow its scope and procedure.
4. Establish the current branch/ref, working-tree or repository state available to you, and the relevant implementation and tests.
5. Record what is established, what is observed in the current state, what remains unresolved, and what is interpretation or proposal.
6. Identify the next concrete action and any assumptions that must not be carried forward without verification.

Do not treat a prior chat summary, previous assistant statement, or remembered plan as a substitute for checking current repository evidence. Conversation context may help identify where to look, but repository state and governing documents determine the current project position.

## Collaboration

The collaboration model distinguishes repository-grounded observation, interpretation and exploration, adjudication, and repository action. These are interacting activities, not mandatory sequential stages or exclusive modes.

Repository contracts and task-specific procedures govern claims and changes within their scope. They do not prohibit independent interpretation, hypothesis formation, alternative explanations, or constructive challenge. Keep evidential status explicit; do not present interpretation as established fact or turn proposals into project policy without adjudication.

Both the user and assistant may question the other's reasoning. Do not accept an interpretation solely because it was stated earlier or appears in a repository note; assess it against relevant evidence, project intent, and applicable contracts.

Conceptual models, diagrams, terminology, and evaluation criteria recorded in the repository are explicit imports into the AI's interpretive space, not prescriptions. Use them as resources for reconstruction and reasoning, not as mandatory workflows or independent authority. Prefer semantically rich terminology where it preserves useful connections and constructive tensions across wider conceptual models. Do not collapse related concepts into one definition or treat their associations as equivalences. Keep local project meanings clear while allowing unresolved differences and alternative interpretations to remain available.

## Continuity across sessions

Session boundaries and limited per-session context are expected. Preserve reconstructability in durable repository records rather than relying on the conversation to carry the work.

When a decision, investigation, or implementation materially changes the working position, update the appropriate project artifact. When work is substantial or a session is nearing its context limit, leave a concise handoff that records:

- current branch/ref and relevant repository state;
- task or issue and its scope;
- work completed and evidence inspected;
- decisions and their rationale, distinguishing adopted decisions from proposals;
- unresolved questions, risks, and known limitations;
- exact current position and the next useful action;
- assumptions or tempting conclusions that the next session must not inherit uncritically.

Update the authoritative document for the information being recorded; do not create competing summaries unnecessarily. A handoff supports ingress but does not replace governing design documents, task records, tests, or source evidence.

See [the collaboration model](docs/collaboration-model.md) for rationale and distinctions.
