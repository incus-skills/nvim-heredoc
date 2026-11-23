# Incremental scan and snapshot-merge contract

**Status:** Review #39 specification closed. This document defines the contract for a future incremental snapshot-merge capability. It does not describe the current implementation and does not authorise implementation by itself.

Related records:
- [Review #39 — Existing-buffer and incomplete-heredoc recovery](https://github.com/incus-skills/nvim-heredoc/issues/39)
- [#46 — Scanner command-group checkpoint observations](https://github.com/incus-skills/nvim-heredoc/issues/46)
- [#47 — Snapshot edit mapping, invalidation, and rescan planning](https://github.com/incus-skills/nvim-heredoc/issues/47)
- [#48 — Bounded rescanning and atomic snapshot merge](https://github.com/incus-skills/nvim-heredoc/issues/48)
- [#49 — One snapshot transaction per `on_lines` batch](https://github.com/incus-skills/nvim-heredoc/issues/49)
- [#50 — Local InsertLeave recovery](https://github.com/incus-skills/nvim-heredoc/issues/50)

## 1. Purpose and scope

The incremental merge contract defines how a previously established scanner snapshot is reconciled with buffer edits without requiring every ordinary edit to trigger a document-wide scan.

It covers:

- mapping old snapshot coordinates through an ordered batch of Neovim buffer edits;
- deciding which old command-group checkpoints are no longer valid;
- identifying the post-edit positions that require fresh lexical interpretation;
- selecting and, when necessary, extending a bounded scan scope;
- deciding which new scan results are safe to retain after a partial failure;
- preserving independently valid snapshot information outside the rescan scope; and
- publishing one coherent snapshot for one owned edit batch.

This contract does not define a general shell parser, document-wide heredoc identity system, or new editing authority. It does not change the Return commitment point or make scanner discovery alone permission to mutate text. The scanner remains a bounded lexical recogniser.

The contract is about the meaning and lifecycle of observations. It deliberately does not prescribe internal data structures, function signatures, or a particular control-flow implementation.

## 2. Terms and coordinate conventions

### 2.1 Snapshot

A snapshot is the scanner-derived interpretation of a buffer at one committed generation. It contains the recognised region information, command-group boundary observations, and a document-level completeness result.

A snapshot is authoritative only after its owning transaction has committed. Temporary scan attempts and partially rebased state are not snapshots.

### 2.2 Command group

A command group is one logical shell command together with the heredoc queue declared by that command. The queue is consumed in declaration order.

A command group may contain no heredocs, one heredoc, or multiple heredocs. Where multiple heredocs are present, the group is complete only after the final queue member has been consumed.

### 2.3 Checkpoint

A checkpoint is an observed boundary at which the scanner has completed a command group and returned to a between-command state:

- the command group's complete heredoc queue has been consumed;
- no heredoc queue member remains pending;
- no continued command remains open; and
- no lexical uncertainty prevents the boundary from being trusted.

A checkpoint is a boundary from which subsequent scanning can begin. It is not inferred merely because a line number follows a terminator-looking line.

Checkpoint positions use 1-based buffer-line boundary coordinates. A checkpoint after command line 25 is the boundary at line position 26: the first line position following that completed command group.

### 2.4 Group key

A group key associates region records with the command group that produced them. It is a coordinate-derived, generation-local association, not a persistent identity for a shell command.

For a given snapshot or scan attempt, all heredoc regions belonging to one command group share its group key. The key is expressed in the coordinate space of the observation that produced it.

Group keys must never be compared across generations or across scan attempts as if they were stable identities. Coordinate equality does not establish lineage or identity.

### 2.5 Neovim edit coordinates

Neovim `on_lines` notifications report zero-based old-buffer coordinates for the replaced interval and a zero-based exclusive end for the resulting interval. The ordered event history must be interpreted in the coordinate space of each event, not as though every event referred to the original buffer.

For reasoning about line positions in this contract:

- convert a resulting event interval `[firstline, new_lastline)` into 1-based line positions `[firstline + 1, new_lastline + 1)`;
- represent scan scopes and checkpoint boundaries as 1-based half-open boundary intervals;
- represent a pure deletion's structural anchor at the first resulting position, `firstline + 1`.

The conversion is important for insertions, deletions, replacements, joins, and splits. A zero-width interval may still carry a structural anchor.

### 2.6 Scan scope

A bounded scan scope is the half-open interval `[S, E)` in full-buffer boundary coordinates. The scanner is supplied the lines beginning at S and ending immediately before E. S is the boundary after a surviving completed command group, or the beginning of the buffer when no earlier checkpoint survives. E is a candidate boundary after the affected footprint, or the end-of-buffer boundary when no later checkpoint is available.

The candidate E is not trusted solely because an old checkpoint existed there. The new scan must independently confirm that it reached E in a safe between-command state.

## 3. Inputs and outcomes

A merge transaction is evaluated against:

- the currently committed old snapshot and its generation;
- the ordered raw edit history belonging to one pending batch;
- the current buffer contents after those edits;
- the pending batch's ownership identity; and
- the scanner's observations from each temporary bounded attempt.

The transaction has three possible outcomes:

1. **Commit a merged snapshot.** The batch still owns the pending work, and the merge either completes its bounded reconciliation or performs the required full-buffer fallback. Exactly one final snapshot is published and the generation advances once.
2. **Discard the batch.** The batch has lost generation or pending-work ownership. It must not publish any snapshot or alter the currently authoritative snapshot.
3. **Require full-buffer fallback.** The batch still owns the pending work, but a bounded-merge precondition is not satisfied. The batch is consumed by a fresh scan of the current full buffer and that result is committed as one new generation.

A fallback is not a discard. A discard is not a failed scan. These outcomes must remain distinguishable.

## 4. Mapping the old snapshot

All old snapshot coordinates must be mapped through the ordered edit history before invalidation, footprint calculation, candidate selection, or preservation decisions are made.

This includes:

- region opener, body, and terminator coordinates;
- command-group keys;
- checkpoint positions; and
- any other old structural line coordinates used by the invalidation rules.

Each event is applied in its own coordinate space, in event order. A later event must not be interpreted using coordinates from before an earlier event has already changed the buffer.

### 4.1 Checkpoint boundary affinity

Command-end checkpoints have **before affinity**.

- An insertion exactly at a checkpoint leaves that checkpoint before the inserted content. The inserted content therefore belongs to the scope that follows the checkpoint and must be considered for rescanning when its position is in the rescan footprint.
- An edit that consumes or replaces the structural boundary on which a checkpoint depends invalidates that checkpoint.
- A checkpoint strictly after an edit is shifted by the edit's line-count delta.
- A checkpoint before an edit remains in place.

The checkpoint's validity is determined by the edit's relationship to the completed command-group structure, not by coordinate movement alone.

### 4.2 Old group-key scope

The mapped old group keys describe only old snapshot records. They are used to determine which old records remain valid, which old records are invalidated, and which old records lie outside the replaced scan scope.

They do not determine whether a newly scanned region is salvageable. That is a separate association described in Section 8.

## 5. Checkpoint invalidation

Checkpoint invalidation and the rescan-required footprint are independent results. They must not be collapsed into one test.

An old checkpoint is invalidated when either of these clauses applies to its command group:

### 5.1 Coordinate-structural invalidation

An edit intersects a known structural line belonging to the group, including:

- a heredoc opener line;
- a heredoc terminator line; or
- a command-structure line whose content or position establishes the logical command boundary.

This clause is based on the old structural coordinates, mapped through the ordered edit history as appropriate. An insertion exactly at a checkpoint does not, by itself, consume the preceding command's completed boundary.

### 5.2 Content-structural invalidation

A resulting line within a mapped heredoc payload interval matches that region's own delimiter under the matching rules of that region's operator.

For the managed `<<-` operator, leading TAB bytes are stripped for matching; leading spaces are not. For ordinary `<<`, matching is exact. The comparison is scoped to the region whose payload contains the resulting line. A line that happens to match another region's delimiter does not invalidate that other region merely by spelling.

This clause detects an important change that coordinate mapping alone cannot detect: inserting an earlier matching delimiter inside a payload can end that heredoc earlier, exposing what used to be opaque payload as shell input. The old terminator may remain present and simply move, but the old command-group interpretation is no longer valid.

A checkpoint is invalidated if either clause applies. Conversely, an edit can require rescanning without invalidating an old checkpoint; see Section 6.

## 6. Rescan-required footprint

The rescan-required footprint R identifies post-edit positions that require fresh lexical interpretation. It is not simply the union of changed lines, nor is it the set of invalidated checkpoints.

[
R = R_{content} cup R_{structural}
]

Both components use the common post-edit, full-buffer coordinate space.

### 6.1 Content footprint

For each edit, consider its resulting line interval. Classify each resulting line position independently.

A resulting position contributes to `R_content` unless it is inside the payload interval of a mapped region and its line does not match that region's delimiter.

Consequences:

- ordinary changed payload content is excluded from lexical rescanning;
- a delimiter-matching line inside a payload is included;
- changed lines outside known payload intervals are included;
- a replacement spanning payload and non-payload positions is classified position by position;
- an insertion inside ordinary payload contributes no content footprint unless its inserted content matches that region's delimiter;
- an insertion of a matching delimiter inside payload contributes a footprint at that position; and
- positions after a delimiter that changes the payload boundary are interpreted as shell input by the subsequent bounded scan.

The rule is applied against the mapped old region intervals and the resulting current buffer lines.

### 6.2 Structural anchors

A coordinate-structural edit contributes a structural anchor even when it produces no resulting line.

- Deleting a structural line contributes an anchor at the first resulting position, `firstline + 1`.
- Replacing a structural line contributes an anchor at the beginning of the replacement, also `firstline + 1`.
- Inserting at a checkpoint does not itself create a structural anchor for the preceding group; the inserted lines are handled by the content footprint.
- A pure deletion may therefore have an empty content interval and a non-empty structural footprint.

The structural anchor is a position requiring interpretation, not a claim that a line exists at that position.

### 6.3 Empty footprint

If R is empty, no structural rescan is required for the batch. The existing structural snapshot remains valid; the changed payload intersection can be handled by the payload-formatting path without rebuilding the lexical interpretation.

This fast path does not authorise un-ranged whole-buffer processing. An empty pending batch must not be interpreted as a request to process the entire buffer.

### 6.4 Independence from invalidation

The invalidated-checkpoint set I and R answer different questions:

- I asks which previously established command-group boundaries can no longer be trusted.
- R asks where new lexical interpretation is required.

A new command inserted at a surviving checkpoint can produce `I = ∅` and `R ≠ ∅`. The old boundary remains valid as the start of the new command's scope, even though the inserted command must be scanned.

A structural deletion can invalidate a checkpoint and contribute a zero-width structural anchor even though no resulting line exists in the event's content interval.

## 7. Selecting and confirming the bounded scan scope

After mapping and invalidation, select boundaries from the surviving old checkpoints.

- S is the greatest surviving checkpoint at or before the first position in R. If none exists, use the beginning-of-buffer boundary.
- E is the least surviving checkpoint at or after the last position in R. If none exists, use the end-of-buffer boundary.

The selected boundaries bracket the entire rescan-required footprint. The scan scope is `[S, E)`.

### 7.1 Candidate confirmation

An old surviving checkpoint is only a candidate far boundary. The new scanner attempt must confirm that the candidate is still a valid between-command boundary in the current text.

Confirmation requires all of the following:

- every supplied line in the candidate scope has been processed;
- the scanner is between commands;
- no heredoc queue member remains pending;
- no continued command remains open; and
- no lexical diagnostic or uncertainty prevents the boundary from being trusted.

A document-level `complete` flag is not, by itself, sufficient to establish completion of an arbitrary bounded scope, nor is it a per-command-group salvage signal.

### 7.2 Candidate extension

If E is not confirmed, extend the far boundary to the next surviving candidate checkpoint, or to the end of the buffer if no candidate remains. Each extended attempt starts again from the same S and scans the enlarged scope from scratch.

A failed attempt's partial parser state is not a resumable continuation. Its observations may inform salvage, but they do not become a committed snapshot or a starting state for the next attempt.

The extension process continues until a candidate is confirmed or the end-of-buffer scope has been examined. The contract imposes no fixed attempt count.

### 7.3 Suffix-completeness precondition

A bounded merge may preserve the old suffix only when the old snapshot provides a sound basis for treating that suffix as independently complete.

Under the current scanner's early-exit contract, an incomplete old document scan cannot have established later checkpoints. Make that assumption an explicit precondition rather than relying on it implicitly:

- after old coordinates have been mapped, if the old snapshot is document-incomplete but any mapped old checkpoint exists at or beyond the selected E, bounded merge is inapplicable;
- if the batch still owns the pending work, consume it through a full-buffer scan and commit that result;
- do not silently preserve a suffix whose completeness cannot be established.

When the old snapshot is complete and a valid checkpoint at or beyond E survives, the suffix beyond that boundary may be preserved independently of the bounded rescan.

## 8. Salvaging results from a failed attempt

A failed bounded attempt can still establish that one or more command groups before the failure completed safely. Salvage is decided at command-group granularity.

### 8.1 Attempt-local observations

Each attempt produces region records and checkpoint observations in the coordinate space of the supplied sub-array. Its group keys are in that same attempt-local coordinate space.

Before any attempt result is merged with full-buffer state:

- translate every attempt region and checkpoint position into full-buffer coordinates using the attempt's S offset;
- translate each attempt region's group key by the same offset; and
- perform the region-to-checkpoint association only after both sides are in that common full-buffer coordinate space.

For an attempt-local line position p, the corresponding full-buffer line is:

[
buffer_line = S + (p - 1)
]

The same translation applies to the attempt-local group key.

### 8.2 New-attempt salvage rule

A new region is salvageable if and only if its attempt's group key appears among that same attempt's checkpoint observations.

- If the key appears, the entire command group is salvageable.
- If the key does not appear, every region in that command group is uncertain.
- The last safe checkpoint is the maximum-position checkpoint observation from that attempt.

This rule deliberately ignores the scanner's blanket confidence downgrade when deciding whether an earlier command group completed. The downgrade remains a conservative scanner-level default for an incomplete document result. The merge-level decision uses the more precise per-group completion observations.

### 8.3 Multiple heredocs in one command group

All heredoc regions declared by one command share one group key and one checkpoint, emitted only after the final queue member has been consumed.

If a command declares three heredocs and scanning fails while searching for the second terminator:

- the first region may have a discovered terminator;
- the second region is incomplete;
- the third queue member has not been consumed; and
- no checkpoint exists for that command group.

All three regions are therefore uncertain. The scanner has not established completion of the command group's heredoc queue. An individual region's terminator does not create a smaller checkpoint or make part of the command group independently salvageable.

### 8.4 Multiple command groups in one attempt

Command groups are independently salvageable. If groups A and B complete and group C fails, the regions belonging to A and B are salvageable because their checkpoint observations exist. All regions belonging to C are uncertain because its checkpoint is absent.

The last safe checkpoint is B's checkpoint. The interval after that checkpoint through the unresolved part of C is uncertain. No checkpoint is asserted inside that uncertain interval.

The same rule applies when a lexical diagnostic causes an early return after one or more completed groups: earlier observed checkpoints remain authoritative for their completed groups; the group in which uncertainty occurs is not salvageable unless its own checkpoint was observed.

## 9. Two independent group-key associations

There are two distinct uses of group keys during a merge. They operate on different observations and must never be joined to each other.

### 9.1 Old-snapshot association

The old snapshot's group keys are mapped through the ordered edit history. They associate old regions with old command groups and their old checkpoints.

This association determines which old records are invalidated, which old records are removed because they fall within the replaced scope, and which records outside the scope remain preservable.

### 9.2 New-attempt association

Each new attempt has its own regions and checkpoint observations. Both are translated from that attempt's local coordinates into full-buffer coordinates. The translated attempt regions are joined only to the translated checkpoint observations from that same attempt.

This association determines which newly discovered command groups completed and which new regions are salvageable after failure.

### 9.3 Worked example: equal coordinates do not mean shared identity

Assume the mapped old snapshot contains a command group whose old group key is full-buffer line 25. An edit changes that command's structure, so the old group is invalidated and its old regions are not retained as valid interpretations.

A new bounded attempt begins at full-buffer boundary S = 11. In the attempt's local coordinates, a newly discovered command group has group key 15 and a checkpoint observation at that same group key.

The attempt-local key translates to:

[
11 + (15 - 1) = 25
]

The numeric full-buffer coordinate is also 25. The new region is salvageable because the new attempt's own checkpoint observation has the translated key 25.

The old region is not thereby revived or associated with the new region. Its old key 25 belongs to the mapped old snapshot and was used in the old-snapshot invalidation decision. The new key 25 belongs to the new attempt and was used in the new-attempt salvage decision. Their numeric equality is incidental; it does not establish identity or allow a cross-generation join.

If the new attempt's checkpoint observation were absent, the new region would be uncertain even though an invalidated old group had previously used the same numeric key. Conversely, a valid old suffix record may be preserved based on its own mapped old checkpoint without being joined to any new attempt region.

**Invariant:** old-snapshot preservation/invalidation and new-attempt salvage are independent associations. Each is evaluated only within its own observation set after that set has been mapped into full-buffer coordinates.

## 10. Merge result and preservation rules

The final merged interpretation consists of:

- old snapshot records outside the replaced scope that remain valid after mapping and invalidation;
- new attempt regions belonging to command groups confirmed by attempt checkpoint observations;
- uncertain representations for the unresolved portion of a failed attempt, where needed to preserve conservative knowledge of the affected scope;
- new attempt checkpoints that were actually observed; and
- an independently preserved suffix only when the suffix-completeness precondition is satisfied.

No checkpoint may be asserted inside an unresolved interval. A region may be uncertain while a preceding checkpoint remains valid. Region confidence and checkpoint validity are separate properties.

On successful bounded reconciliation, document-level completeness is derived from the bounded result and the independently established suffix state. On an unresolved failure, document-level completeness remains false. A partial scan's document-level result must not be mistaken for proof that every earlier group failed.

Old records inside the replaced scope are replaced by the new attempt's interpretation; they are not merged by matching their old group keys to new group keys. Old records outside the scope are retained only if their mapped structural coordinates and required checkpoints remain valid.

## 11. Transaction and publication invariants

The merge is one transaction for one owned pending edit batch.

### 11.1 Entitlement

The transaction is entitled to proceed only while:

- the batch's base generation equals the currently committed snapshot generation; and
- the batch still owns the pending work for that buffer.

If either condition is false, discard the batch without scanning or publishing a snapshot.

Check entitlement before doing merge work. Check it again immediately before publication. The current Neovim event loop is synchronous during this operation, but the final check is part of the transaction contract and must remain correct if a future refactor introduces yielding or asynchronous boundaries.

### 11.2 Fallback versus discard

If the batch still owns pending work but a bounded-merge precondition fails, perform the specified full-buffer fallback against the current buffer and commit its result as the batch's single new generation.

If ownership or generation entitlement has been lost, discard the batch. Do not run a fallback that could overwrite a newer committed snapshot.

### 11.3 Atomic publication

All coordinate mapping, filtering, scan attempts, candidate extension, salvage decisions, suffix preservation, and document-completeness derivation are provisional until the final commit.

No intermediate rebased snapshot, failed candidate result, or partially salvaged state may become authoritative.

A committed batch:

- publishes exactly one final snapshot;
- clears only the pending work it owns; and
- advances the snapshot generation exactly once, regardless of how many edit ranges or scan attempts were involved.

A discarded batch publishes nothing and does not advance the generation. A failed candidate attempt does not independently advance the generation.

### 11.4 Empty pending work

An empty pending queue is not a request for an un-ranged full-buffer processing pass. The absence of pending edits must not silently re-enter a whole-buffer mutation path.

This invariant is especially important for InsertLeave: leaving Insert mode must not turn an empty or unrelated pending batch into document-wide formatting or incomplete-region recovery. The local InsertLeave responsibility is specified separately in [issue #50](https://github.com/incus-skills/nvim-heredoc/issues/50).

## 12. Failure behaviour summary

| Condition | Required result |
|---|---|
| R is empty | Retain valid structural snapshot; process only the changed payload intersection. |
| Candidate E is confirmed | Merge the bounded interpretation with valid old prefix/suffix state. |
| Candidate E is not confirmed | Extend to the next candidate and rescan from the same S. |
| Earlier groups completed, later group fails | Salvage completed groups using the attempt's checkpoint observations; mark the failing group uncertain. |
| Failure occurs between heredoc queue members | Treat every region in that command group as uncertain; no group checkpoint exists. |
| Lexical diagnostic follows completed groups | Preserve completed groups with observed checkpoints; do not salvage the uncertain group. |
| Old snapshot incomplete but mapped checkpoint exists at or beyond E | Bounded merge is inapplicable; use full-buffer fallback if batch ownership remains valid. |
| Batch generation or ownership is stale | Discard; do not scan or publish over newer state. |
| Final entitlement check fails | Discard provisional work; do not publish. |
| Multiple ranges or candidate attempts belong to one batch | Still one final publication and one generation advance. |

## 13. Validation obligations

The contract is not considered implemented merely because isolated planner or scanner tests pass. Validation must cover both the independent capabilities and their composition.

### 13.1 Scanner observation tests

The scanner test layer must establish:

- one checkpoint after a single-heredoc command group;
- one checkpoint after the final member of a multiple-heredoc queue;
- no checkpoint when failure occurs between queue members;
- earlier group checkpoints retained when a later group is incomplete;
- earlier group checkpoints retained when a later lexical diagnostic causes early termination; and
- correct attempt-local coordinate association.

### 13.2 Mapping and planning tests

The edit-mapping/planning test layer must establish:

- ordered mapping for insertion, deletion, replacement, join, and split;
- before-affinity for checkpoint boundaries;
- coordinate-structural invalidation;
- content-structural invalidation for a matching delimiter inserted into a payload;
- per-region delimiter scoping;
- zero-width structural anchors;
- payload-only edits producing an empty rescan footprint;
- a new command at a checkpoint producing a non-empty footprint without requiring old-checkpoint invalidation; and
- the suffix-completeness guard.

### 13.3 Merge and event-path tests

The Neovim buffer-integration layer must exercise the six cases through the actual `on_lines` event and scheduled batch path:

1. payload-only edit;
2. opener delimiter change;
3. terminator deletion;
4. continuation edit;
5. earlier matching terminator inserted inside payload; and
6. new command inserted at a checkpoint.

It must additionally cover candidate extension, multi-queue failure, later-group salvage, lexical early return, offset translation, stale ownership, fallback versus discard, multi-range batches, empty pending work, atomic publication, and one generation advance per committed batch.

The empty-pending-queue/no-un-ranged-processing regression must be the first InsertLeave test. It directly protects the adjudication that InsertLeave must not fall back to un-ranged document-wide processing. The diagnostic behaviour recorded in [PR #45](https://github.com/incus-skills/nvim-heredoc/pull/45) is evidence of the old behaviour, not the acceptance expectation for the revised contract.

### 13.4 Existing CI layers

The existing five CI jobs remain the validation structure:

- **Core scanner:** passive scanner observations and command-group completion.
- **Neovim buffer integration:** mapping, planning, merge transactions, and actual event-path behaviour.
- **Shell delivery:** exact payload delivery remains independently verified.
- **Formatter:** payload preservation remains independently verified for the supported formatter fixtures.
- **LazyVim integration:** plugin coexistence remains independently verified.

This specification does not require a sixth CI job. It requires the relevant existing jobs to be extended without collapsing their independent evidence.

## 14. Implementation boundary and status

This document closes the Review #39 specification. It is not evidence that the described capability exists in the current code.

Implementation is subdivided into independent, reviewable work:

- scanner observations: [#46](https://github.com/incus-skills/nvim-heredoc/issues/46);
- coordinate mapping and rescan planning: [#47](https://github.com/incus-skills/nvim-heredoc/issues/47);
- bounded scan and atomic merge: [#48](https://github.com/incus-skills/nvim-heredoc/issues/48);
- event-batch transaction integration: [#49](https://github.com/incus-skills/nvim-heredoc/issues/49); and
- local InsertLeave responsibility: [#50](https://github.com/incus-skills/nvim-heredoc/issues/50).

Scanner observations and coordinate planning are independent capabilities and may be developed and validated in parallel. The bounded merge composes them. Event-path integration consumes the merge as one batch transaction. InsertLeave must coordinate with the event-batch ownership interface and may also use bounded scanning for contextual recovery; this is an interface coordination requirement, not a strict implementation-order dependency.

The scanner's existing lexical decomposition remains intact. The possibility of future Tree-sitter-based syntax presentation is preserved as a potential consumer of structural distinctions, not as an implementation requirement for this work.

Diagnostic PRs [#44](https://github.com/incus-skills/nvim-heredoc/pull/44) and [#45](https://github.com/incus-skills/nvim-heredoc/pull/45) remain empirical records of current behaviour. They are not implementations of this contract and their observed cross-region InsertLeave effects are not the desired behaviour.

No implementation is authorised by the closure of Review #39 or by the existence of these backlog issues.