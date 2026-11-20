# Task 002 — Lexical-zone syntax presentation (deferred)

**Status:** deferred — future development; no current implementation work is authorised  
**Priority:** future development  
**Current disposition:** the lexical-zone policy is adopted. The distinct-delimiter regression fixture and its scanner, shell-delivery, and formatter checks are recorded as completed evidence. Broader syntax-presentation work is reserved for a separately authorised future effort.

## Adopted policy

The governing policy is recorded in the design contract and future-development context:
- An established heredoc body is a lexical zone distinct from the active syntax of its containing shell document.
- Its boundary is authoritative for editing behaviour and syntax representation.
- A non-colliding inner payload construct must not be adopted as active syntax of the containing shell document.
- A line matching the enclosing delimiter under the enclosing shell operator's matching rules is the enclosing heredoc terminator, not payload. Keep that shell-delivery collision distinct from non-colliding payload fixtures.
- Structural recognition, payload-language classification, presentation, language services, and mutation/formatter policy are separate concerns.
- Unknown payloads remain opaque; uncertainty about language does not permit the containing shell parser to claim the payload as shell syntax.
- Tree-sitter injection is one possible future presentation mechanism, not the authority for establishing the host lexical boundary.

**Defer how the payload is represented, not whether its lexical boundary is respected.**

## Completed investigation and regression evidence

The canonical non-colliding cargo fixture uses distinct outer (EOF) and inner (FOE) delimiters. It is appropriate for testing the scanner's lexical-zone boundary and shell-delivery behaviour. The same-delimiter case remains a separate collision fixture: under Bash <<- matching rules, a hard-left line matching the outer delimiter terminates the outer heredoc too.

The fixture at tests/fixtures/heredoc-cargo-distinct-delimiters.sh is covered by:
- The Lua scanner suite, which asserts one complete outer region and keeps the inner opener/terminator within its body.
- Shell-delivery tests, which compare delivered payload bytes under Bash, Dash, and Zsh when available.
- Formatter tests, which compare delivered payload before and after shfmt.

The same-delimiter collision remains separately represented. These tests distinguish scanner-derived region recognition, shell-delivered bytes, and formatter preservation. They do not establish Tree-sitter parse-tree containment or visual highlighting behaviour.

Hosted workflow run 44640744894 completed successfully across all five jobs: core scanner, Neovim buffer integration, shell delivery, shfmt payload preservation, and LazyVim plugin coexistence.

This is evidence for those repository test layers only. The workflow does not install or pin nvim-treesitter or the Bash Tree-sitter parser, and does not inspect parse-tree node ranges or query captures. A green run therefore does not establish syntax-presentation containment.

## Historical source observations

Earlier source inspection recorded nvim-treesitter revision 19bdfc04f40ed2ccb3340591d125f759b0406875 and Bash grammar revision a06c2e4415e9bc0346c6b86d401879ffb44058f7. At those revisions, the standard Bash highlight and injection queries consumed parser-produced heredoc nodes; they did not consume the nvim-heredoc scanner's region range.

Those observations establish that parser output and plugin-established boundaries are distinct sources of information. They did not establish the exact parse-tree failure in a target Neovim buffer, identify a root cause, or validate a corrective presentation mechanism. No root-cause diagnosis is claimed. The CI diagnostic gap is retained as historical context, not as an outstanding current action.

## Future development direction

When explicitly reopened, consider syntax presentation as part of a broader embedded-language capability, not merely a Bash heredoc highlighting fix. Possible payloads include Python, Rust, Markdown/markup, and other embedded languages. Tree-sitter injections may be useful, but are only one candidate mechanism.

Any future design must keep separate: (1) the authoritative host structural boundary; (2) payload-language classification, with unknown content remaining opaque; (3) presentation consuming the established region; (4) region-aware diagnostics, completion, LSP, and linting; and (5) formatter and other mutation policy.

Future investigation may examine parser-tree node ranges, query captures, parser/API compatibility, injection lifecycle, language selection, unknown-language fallback, and integration behaviour across multiple host/payload combinations. These are not current actions or acceptance prerequisites.

## Constraints to retain when future work is authorised

- Do not make Tree-sitter a dependency for closer insertion or payload editing.
- Do not use the Bash parser as the source of the payload boundary.
- Do not assume recolouring a terminator is sufficient if the containing parse still claims payload.
- Do not assume injection alone solves host-parser containment or language services.
- Do not hard-code delimiter names; consume the established region.
- Do not default unknown payloads to Bash.
- Do not disable editor tooling buffer-wide as a substitute for region containment.
- Preserve normal host-language behaviour before and after the payload region.
- Keep diagnostics, completion, LSP, linting, and formatter isolation as separate integration questions unless a demonstrated dependency joins them.

## Reopening gate

Reopen this record only when broader embedded-language presentation work is explicitly authorised. At that point, begin with the current scanner/region interface, the current design contract, and verified installed parser/integration APIs. State the target host and payload cases, evidence requirements, and acceptance criteria before implementation.

Until then, no parser-tree diagnosis, query changes, injection implementation, grammar changes, highlighting changes, or language-service integration is implied or requested.
