# Collaboration model and session continuity

**Status:** adopted collaboration principles; the topology diagram is a conceptual representation, not a prescribed workflow.

This document describes how the user and assistant collaborate on this repository, how different kinds of reasoning are kept distinct, and how work remains reconstructable across sessions. It is an epistemic and operational agreement, not a technical design for the plugin.

## Why this model is explicit

Repository work is conducted across sessions with limited per-session context. A later session may not have access to the full reasoning that led to the current position. The collaboration therefore cannot depend on conversational continuity or on an assistant reproducing an earlier session's conclusions.

The repository must preserve enough durable context for a new session to reconstruct the current working position, understand why important decisions were made, identify what remains open, and continue without treating missing context as permission to guess.

The purpose of ingress is to restore the conditions for productive reasoning—not to prescribe conclusions or reproduce every step of a previous conversation.

## Four interacting activities

The collaboration distinguishes four activities. They are useful distinctions, not sequential stages, exclusive roles, or a mandatory traversal.

### 1. Repository-grounded observation

Establish what the repository and its execution environment actually show.

This includes inspecting source, tests, documentation, dependencies, configuration, versioned history, issue/task records, and observed behaviour. Preserve provenance: distinguish what a source explicitly states from what a test demonstrates, what a tool reports, and what is inferred from those observations.

Repository-grounded observation is not limited to confirming an existing interpretation. It may expose contradictions, omissions, unexpected behaviour, or evidence that challenges an adopted explanation.

### 2. Interpretation and exploration

Identify patterns, make connections, formulate hypotheses, consider alternatives, and explore consequences.

This activity is deliberately open. It is not restricted to conclusions already documented in the repository or to the immediate wording of an active task. A useful interpretation may reveal that a requirement is incomplete, that an earlier explanation is weak, or that a different framing deserves investigation.

Exploratory contributions are not automatically repository facts or project decisions. Their evidential status must remain visible.

### 3. Adjudication

Examine interpretations and proposals against observed evidence, project intent, language and tool semantics, existing technical contracts, and the consequences of adopting them.

Adjudication may accept, reject, qualify, defer, or reopen an interpretation. It may lead back to further observation or exploration. Neither an earlier assistant conclusion nor a repository statement is immune from examination; equally, an attractive hypothesis does not become established merely through discussion.

A decision becomes project policy only when it is explicitly adopted and recorded in the appropriate authoritative artifact.

### 4. Repository action

Translate sufficiently adjudicated decisions into appropriately scoped repository changes: documentation, tests, code, issues, or other project records.

Repository action should preserve the distinction between adopted requirements and implementation choices. A change does not become correct merely because it is implemented or passes a test; validation must address the intended behaviour and relevant evidence.

Implementation and testing may also reveal new evidence or questions, feeding back into observation, interpretation, and adjudication.

## Relationship topology

The activities interact. The following flowchart represents their relationships without imposing a required order of traversal. The dotted, non-directional connections indicate observational or relational association, not a control-flow transition or a claim that one activity must follow another.

```mermaid
flowchart TD
    subgraph collaboration["Collaboration activities"]
        O["Repository-grounded observation"]
        I["Interpretation and exploration"]
        A["Adjudication"]
        R["Repository action"]

        O -.-|"Evidence, provenance and observed conditions"| I
        I -.-|"Hypotheses, alternatives and conceptual connections"| A
        A -.-|"Critical examination and requests for verification"| O
        A -.-|"Adopted distinctions, decisions and constraints"| R
        R -.-|"Implementation, consequences and validation evidence"| O
        R -.-|"New questions, tensions and emergent possibilities"| I
    end
```

The labels are semantic entry points into the interfaces, not exhaustive inventories of what may pass between activities. They name characteristic exchanges while leaving room for other relationships to become visible through experience. The dotted edges remain observational and relational: their labels do not establish a mandatory direction, sequence, ownership boundary, or required transaction.

The diagram is intentionally modest. It distinguishes the activities and makes their interdependence visible without attempting to contain the full interpretive space. The interface descriptions and the repository's technical/task contracts provide context, but do not prescribe a universal collaboration procedure.

The interface topology can be read through several wider conceptual lenses: evidence and provenance; hypothesis formation and abductive exploration; critical deliberation; decision rights and constraints; implementation feedback; and learning from consequences. These lenses are related but not interchangeable. Their differences are useful interpretive resources rather than distinctions this diagram attempts to settle.

## Cross-cutting principles

### Interpretive freedom

Repository instructions, technical contracts, and task procedures constrain claims presented as established and changes made within their scope. They do not prohibit independent reasoning, hypothesis formation, alternative explanations, or constructive challenge.

A task-specific investigation procedure governs that task. It must not silently become a universal restriction on all reasoning in the repository.

### Epistemic separation

Keep these categories distinguishable:

- **Observation:** what a source, test, tool, or execution actually shows.
- **Established project decision:** a requirement or policy explicitly adopted and recorded in an authoritative project artifact.
- **Interpretation:** an explanation or reading of available evidence.
- **Hypothesis:** a proposition that may explain observations but remains to be tested.
- **Alternative:** another plausible interpretation or approach.
- **Proposal:** a suggested decision or change not yet adopted.

These categories may evolve: a hypothesis can be tested, an interpretation can be adjudicated, and a proposal can be adopted or rejected. Do not silently promote one category into another.

### Mutual challenge

The user and assistant may both question assumptions, evidence, and conclusions. Neither should merely mirror the other's latest statement. Disagreement should be reasoned and specific, with uncertainty and supporting evidence made visible. Corrections should improve shared understanding rather than unnecessarily narrow future exploration.

## Session continuity and ingress

### Session boundaries are expected

A session may end because of context limits, interruption, a change of task, or a deliberate handoff. The next session must not depend on access to the previous conversation.

The repository is the durable working environment. Documentation and ingress instructions are continuity surfaces: they preserve enough structure and provenance for a different observer, at a later time, to reconstruct the current position. They are not intended to preserve every conversational detail.

### What ingress must establish

A new session should, to the extent relevant to its task:

1. Identify the repository, current branch/ref, and available working state.
2. Read the repository ingress instructions and this collaboration model.
3. Identify the active task or issue and understand its actual scope and governing procedure.
4. Read the relevant technical contracts and authoritative project records.
5. Inspect the current implementation, tests, dependencies, and configuration needed to verify the reported position.
6. Separate established decisions and direct observations from interpretations, hypotheses, alternatives, and proposals.
7. Identify unresolved questions, known limitations, and the next useful action.
8. Avoid inheriting unverified assumptions or treating conversational summaries as authoritative evidence.

Ingress should be proportionate. It should direct a session to the relevant context, not require loading the entire repository or every historical discussion. When the correct next step is uncertain, inspect the governing records and evidence before asking the user to repeat information that may already be recorded.

### What a useful handoff preserves

When work materially changes the project position, or when a session is nearing its context limit, record a concise handoff in the appropriate durable location. It should preserve:

- the branch/ref and relevant repository state;
- the task or issue, its scope, and the current position within it;
- the files, tests, dependencies, or behaviours actually inspected;
- work completed and its evidence;
- decisions adopted and the rationale for them;
- interpretations, hypotheses, and proposals that remain provisional;
- unresolved questions, risks, limitations, and failed or inconclusive approaches;
- the exact next action and any assumptions the next session should avoid.

Record information in the artifact that owns it. Technical requirements belong in the technical design contract; task progress belongs in the task record; broader collaboration and ingress rules belong here and in `AGENTS.md`. Avoid duplicating full explanations across multiple documents. A handoff should point to authoritative records rather than create a competing source of truth.

### Continuity is not conclusion preservation

A new session should inherit the evidence, adopted decisions, open questions, and current work position—not an obligation to defend the previous session's interpretation. Reconstructability requires enough provenance to understand why the current position exists, while retaining the freedom to challenge it when new inspection or reasoning warrants doing so.

## Conceptual imports and semantic compression

The models, distinctions, terminology, diagrams, and criteria in this document are explicit conceptual imports into an AI interpretive space. They are intended to make relationships and wider conceptual associations available to an incoming observer. They are not prescriptions, exhaustive descriptions, mandatory workflows, or independent sources of authority.

Terminology should be used for **semantic compression without conceptual closure**. A compact term can connect the observer to wider conceptual models and methodologies represented in the training corpus, allowing those associations to inform interpretation without requiring the repository to reproduce them in full. The purpose is not to make a term appear more exact by reducing it to one definition.

Semantic compression should preserve constructive tension:

- **Resonance without reduction:** a term may activate related concepts without declaring them equivalent.
- **Plurality without forced synthesis:** competing interpretations and methodological differences may remain visible where they are productive.
- **Precision without premature closure:** project-specific usage should be clear enough to support communication while leaving wider conceptual associations open.
- **Affordance without authority:** an imported concept offers ways to reason; it does not determine the conclusion or confer authority.
- **Reconstructability without canonisation:** preserve the relationships, tensions, provenance, and unresolved questions needed for later observers to reconsider the interpretation.

For example, recursive improvement may resonate with feedback control, reflective practice, evolutionary adaptation, and learning systems. These perspectives do not describe one identical mechanism. Their different assumptions about feedback, agency, stability, selection, and change can help expose questions that a single narrow definition would conceal.

Where a term has a specific meaning within this repository, explain that local usage without implying that it exhausts the wider concept. Do not turn a useful conceptual association into a hidden requirement, or present a model's familiar methodology as an adopted project procedure merely because the terminology evokes it.

### Recursive evaluation of ingress and continuity

The concern that ingress effectiveness has not yet been demonstrated can be approached through recursive evaluation. This is an imported feedback model for examining reconstructability, not a prescribed sequence that every session must execute mechanically.

A new observer's reconstruction can be considered against several dimensions:

- **Position:** can the observer identify the relevant branch/ref, task, current work position, and next useful action?
- **Contract discovery:** can the observer locate the technical and procedural contracts relevant to the work without treating task-local rules as universal?
- **Provenance:** can direct observations, source claims, test results, inherited interpretations, and hypotheses be distinguished?
- **Decision status:** can adopted decisions be distinguished from provisional interpretations, alternatives, proposals, and unresolved questions?
- **Continuity:** can the observer identify what has been completed, what remains open, and why the next action is appropriate?
- **Interpretive freedom:** does the imported context support independent examination and constructive challenge rather than obliging the observer to defend inherited conclusions?
- **Context economy:** does the ingress identify sufficient relevant context without requiring indiscriminate loading of the repository or historical conversation?

These are evaluation dimensions, not a pass/fail checklist or an exhaustive specification. Their relevance and weight depend on the task and observer position. A reconstruction may be sufficient for one task while remaining incomplete for another.

Observed deficiencies can become inputs to further interpretation and adjudication. A proposed correction may concern an ingress instruction, a handoff, a technical contract, a task record, or the collaboration model itself. The appropriate authoritative artifact should own the correction. A discrepancy does not automatically authorise a repository change: proposed adaptations remain subject to the project's ordinary adjudication and change authority.

Subsequent ingress experiences can provide further evidence about whether an adaptation improved reconstructability, introduced new ambiguity, or displaced a useful tension. In this way, evaluation, interpretation, adjudication, and repository action can recursively inform one another without becoming an automatic self-modification loop.

The distinction between two evaluation concerns should remain available:

- **Ingress effectiveness:** whether an incoming observer can reconstruct enough of the working position to proceed responsibly. Cold-start reconstruction exercises can provide direct evidence.
- **Collaboration effectiveness:** whether the interfaces between observation, interpretation, adjudication, and repository action support productive reasoning and sound outcomes. This is broader and cannot be established by ingress checks alone.

A conceptual feedback topology is:

```mermaid
flowchart TD
    A["Incoming observer reconstructs working position"]
    B["Reconstruction is examined against task-relevant evidence and criteria"]
    C["Gaps, tensions or misleading context become visible"]
    D["Interpretation and adjudication consider possible adaptations"]
    E["An authorised change is made to the appropriate durable artifact"]
    F["A later ingress provides further evidence"]

    A -->|"Reconstructed position and provenance"| B
    B -->|"Sufficient for this task"| F
    B -->|"Deficiency or uncertainty exposed"| C
    C -->|"Candidate explanation or correction"| D
    D -->|"Adopted change, if warranted"| E
    E -->|"Changed continuity conditions"| F
    F -.->|"Feedback for renewed interpretation"| A
```

This diagram represents a possible feedback relationship, not a required lifecycle or an instruction to modify repository artifacts whenever a criterion is unmet. In particular, the path from an observed deficiency to an authorised change is mediated by interpretation and adjudication; it is not automatic. A later ingress may confirm, qualify, or challenge the apparent improvement.

## Scope and authority

This document governs collaboration and session continuity. It does not supersede technical contracts such as [the design contract](design.md), nor does it replace task-specific scope and procedures. Where a task defines a particular investigation method, apply it within that task. If a conflict with an adopted project policy is found, make the conflict and its impact explicit and seek adjudication rather than silently overriding either source.

Related ingress instructions: [repository AGENTS.md](../AGENTS.md).
