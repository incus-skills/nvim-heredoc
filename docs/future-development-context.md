# Future development context: embedded heredoc payloads

**Status:** mixed: the lexical-zone boundary policy below is adopted project policy; the choice and implementation of payload presentation, language classification, and region-aware editor integrations remain future-development work.

This note records both the adopted boundary policy and the still-open design questions for embedded payload support. It is intended to survive context changes and help a fresh contributor or AI session distinguish settled requirements from unresolved implementation choices.

## Project-level design test and scope

The project exists to provide proper, predictable heredoc editing and autoformatting in LazyVim, while remaining usable as a normal Neovim plugin. The governing design test is:

**Is this how heredocs should behave in the editing experience?**

Do not replace that question with either of these narrower tests:

- Does the editor reproduce every native shell behaviour as its user experience?
- Can the implementation extend the shell's own semantics to support an editor feature?

Native shell semantics remain authoritative evidence about what a script means and what bytes the receiving command gets. They are constraints that editing, formatting, and delivery behaviour must respect; they are not, by themselves, the specification for the best editing experience. Where a useful editor behaviour differs from the shell's native behaviour, the distinction and any required representation or transformation must be explicit, tested, and must not silently change the script's delivered meaning.

### Native `<<-` behaviour is not nested indentation accounting

For a shell `<<-` heredoc, the shell strips all leading TAB bytes from each line of that heredoc body, and applies the same TAB-stripping rule when matching its terminator. It does not track nested heredoc depth, maintain relative indentation levels, or select a particular indentation index to strip. Text that will later become an inner heredoc is still just text in the outer heredoc body at this stage.

Consequently, an outer `<<-` can remove TABs intended as indentation in a nested heredoc before the inner script is ever interpreted. Preserving those TABs for a later inner `<<-` requires an explicit representation or transformation; it cannot be obtained by asking Bash's outer `<<-` to recognise and exempt the inner lexical zone.

This is a shell-delivery fact and a design constraint. It does not prescribe that the plugin should emulate Bash's stripping as its editing indentation model, nor does it establish placeholder substitution, expansion, or another encoding as project policy. Any proposed nested-heredoc behaviour must be assessed against the editing goal and verified at both stages: the bytes produced by outer processing, and the behaviour when the generated inner script is executed.

### Keep extensions separate from the core editing test

Nested heredoc indentation and embedded-language syntax presentation are related extensions, but neither should silently expand the acceptance criteria for the core heredoc editing and autoformatting work.

- **Core editing and formatting:** establish predictable opener/closer handling, structural indentation, paste preservation, and formatter coexistence in the LazyVim workflow. Verify that the resulting shell source retains its intended delivery semantics.
- **Nested heredoc handling:** investigate separately where the desired editing representation needs to preserve inner indentation across an outer shell's native TAB stripping. Do not assume the shell already provides nested indentation levels.
- **Embedded-language presentation:** investigate separately how payload regions might be highlighted or parsed as another language. Tree-sitter injection is one possible mechanism, not a prerequisite for the core editing/formatting test and not an authority for shell-delivery semantics or region boundaries.

The lexical-zone policy recorded below remains the project's intended boundary distinction. However, implementing a Tree-sitter injection, diagnosing every host parse-tree capture, or providing general embedded-language presentation is not a condition for considering the core heredoc editing behaviour successful. These investigations should remain explicitly scoped and should be promoted into implementation requirements only through a separate design decision.

## Adopted project policy: lexical-zone boundary

An established heredoc body is a lexical zone distinct from the active syntax of its containing shell document. This boundary is authoritative for both editing behaviour and syntax representation.

- The plugin must not recursively interpret payload text as active shell syntax. Embedded opener-looking lines and delimiter-looking lines remain payload for the containing heredoc.
- The containing shell syntax parse must not adopt constructs inside that payload zone. In particular, an inner heredoc terminator such as `EOF` must not be interpreted as the terminator of an outer Bash heredoc.
- The boundary is independent of payload-language classification. A payload may be known, inferred, or unknown; uncertainty about its language does not permit the containing shell parser to claim it as shell syntax.
- The eventual presentation may use a contained-language parser/injection or opaque content. The project has not yet selected that presentation strategy, nor has it committed to a particular language-classification mechanism.
- Tree-sitter injections are a possible future consumer of the established body range, not the authority that establishes the range or the structural source of truth.
- The current Tree-sitter Bash behaviour that adopts an inner `EOF` as an outer-shell terminator is a known mismatch with this policy. Deferring the choice of visual representation does not make that incorrect outer-shell interpretation acceptable.

This policy does not require immediate implementation of a particular injection, parser, or highlighting mechanism. It does establish the invariant that any future visual representation must respect: **defer how the payload is represented, not whether its lexical boundary is respected.**


## The concern: a shell buffer can contain non-shell payloads

A Bash, POSIX `sh`, or Zsh buffer may contain a heredoc whose body is Markdown, JSON, YAML, TOML, another programming language, a template, plain text, or an application-specific format. The enclosing buffer's filetype remains the shell filetype, but the body is not necessarily shell source.

Consequently, shell-oriented editor tooling may be inappropriate inside the body:

- shell diagnostics and linting may report irrelevant errors;
- shell completion may offer suggestions that do not belong to the payload language;
- shell formatting may rewrite payload syntax or whitespace;
- other shell-aware editing features may interpret payload text as shell constructs.

A concrete failure mode discussed was a Markdown fenced code block being transformed by a shell formatter into shell command-substitution syntax. This is an example of the risk, not a claim that every shell formatter behaves this way for every fixture.

The existing formatter tests establish payload preservation only for the specific Bash and POSIX-shell fixtures exercised. They do not establish safety for arbitrary embedded languages or arbitrary payload content.

## A useful precedent: embedded-language handling in a mise Neovim configuration

The user supplied an existing Neovim configuration used for mise files. The supplied excerpt is TOML-oriented and demonstrates several distinct mechanisms:

1. **File-context recognition:** a custom Tree-sitter predicate identifies mise-related TOML files, so mise-specific query behaviour is not applied indiscriminately to every TOML buffer.
2. **Tree-sitter injections:** TOML `run` values are injected as shell languages. The query uses shebangs where available, applies content offsets to exclude TOML multiline-string delimiters, and has fallback language choices for cases without a shebang.
3. **Additional query predicates and injections:** specially marked comments in Bash/Python and Go/Rust sources are injected as TOML or KDL, including prefix offsets and combined-node handling.
4. **Language-server availability:** Otter is activated for selected languages in matching mise TOML files, making embedded-language LSP features such as completion available.

This is a precedent to study, not a design to copy wholesale. In particular:

- A Tree-sitter injection gives a region an embedded language identity for parsing/highlighting; it does not change the enclosing buffer's filetype.
- Injection and language-service activation are separate concerns. Activating Otter for a set of languages does not, by itself, prove that diagnostics or completion are correctly restricted to each injected region.
- The supplied excerpt is TOML-specific. Do not infer from it that the same configuration already handles every mise file format.
- A heredoc delimiter usually does not identify the payload language as directly as a mise `run` field's shebang can. Language identification may need a separate mechanism or may remain unknown.

## Payload declarations and language identity

The heredoc delimiter is structural only: it identifies the shell boundary and must not be overloaded to imply a payload filename, filetype, interpreter, or presentation mode.

Payload language identity should preferably come from a declaration in, or explicitly associated with, the payload. Recognition of existing conventions is preferred over inventing a new in-body syntax:

1. **Shebangs:** a leading shebang such as `#!/usr/bin/env bash` is an explicit declaration of script interpreter/language. It is genuine script content and remains part of the delivered payload.
2. **Editor modelines:** an applicable modeline may declare a filetype. It is editor metadata expressed using the target language's comment syntax where available. Modeline recognition must be associated with the particular heredoc region; Neovim's buffer-level `filetype` is not a substitute for per-region language identity.
3. **Filename or path metadata:** an explicitly supplied filename or path with an extension can identify the intended file and language. Do not heuristically interpret an arbitrary first line such as `# config.yaml` as a filename declaration; that is not a standardised convention.
4. **Unknown or unsupported declarations:** retain an unknown/opaque payload rather than guessing. A narrow explicit fallback may be considered later for formats without a natural declaration, but its syntax and delivery semantics are not decided.

A shell-looking comment marker inside an established heredoc body is payload, not a shell comment: the shell delivers it to the receiving command. Any future fallback marker must therefore specify whether it is real payload content or editor-side metadata, and how it is excluded from or retained in shell-delivered bytes. Do not assume that a line resembling a shell comment is automatically harmless.

The declaration travels with the payload, so language identity need not depend on whether content arrived through `:r! cat`, another import operation, paste, or manual editing. Import provenance may still provide useful explicit metadata, but it is not the only source of language identity and must not be confused with the structural boundary.

The preferred policy is to recognise existing declarations where valid and supported, with conservative handling when none is available. Do not infer language from the delimiter. Do not treat the downstream command as a general language declaration: consumer context can be supplementary evidence in a future classification model, but it is not the primary declaration policy and must not override an explicit payload declaration without a separately specified conflict rule.

## Initial syntax-presentation case: Bash scripts

The first concrete payload-language case selected for future syntax presentation is a Bash script whose body begins with:

```bash
#!/usr/bin/env bash
```

This is a deliberately narrow starting case. The shebang is an existing, explicit declaration; it remains part of the script delivered by the shell. A future presentation mechanism may use it to select Bash parsing/highlighting for the scanner-established body region.

This selection does not authorise implementation of a Tree-sitter query or injection yet. It does not establish how a region-specific language association is represented, how the declaration is recognised and kept in sync as the body changes, or how an injection API obtains that association. Those remain implementation questions for the broader embedded-language work. The containing buffer retains its shell filetype, and the heredoc delimiter remains purely structural.

## Architectural distinction to preserve

The governing editing decision is Return-local bounded scope: Return after a completed managed opener commits the plugin to inserting its matching closer immediately, and that closer bounds the payload region. The scanner is a bounded lexical helper for recognising the opener/delimiter and supporting consumers; it is not a mandate for a document-wide heredoc ownership graph. Future embedded-language work should consume the established local body/closer boundary while keeping these questions separate:

1. **Structural recognition — where is the payload?**  
   For interactive creation, Return establishes the local boundary by inserting the matching closer. The scanner supplies bounded lexical recognition; it does not need to maintain document-wide opener identity or discover the closer by searching later source. Embedded-language consumers should use the established body range rather than inventing independent boundary heuristics.

2. **Payload classification — what is the payload language?**  
   A body may be identified as a known language, inferred with some confidence, or remain unknown/opaque. Structural recognition must not depend on successful language classification.

3. **Presentation — how is the payload parsed and highlighted?**  
   The adopted policy requires the containing shell parse not to claim payload content as active shell syntax. The specific presentation remains open: a Tree-sitter injection or another contained-language mechanism may be used, or the region may remain opaque. Any such mechanism must consume the established body range; it must not become the authority for shell heredoc structure, especially in incomplete editing buffers.

4. **Language services — which tools may operate in the region?**  
   Diagnostics, completion, LSP features, linting, and related services need their own region-aware integration. Availability of an embedded parser or language server is not proof that requests and diagnostics are scoped correctly.

5. **Mutation policy — which tools may rewrite the payload?**  
   Formatters and other mutating tools need particular care. A tool appropriate for the surrounding shell source may be inappropriate for the body. Any future formatter integration must preserve payload semantics and bytes according to an explicit policy, with tests for the actual tool and configuration.

The desired direction is not necessarily to disable every shell feature for an entire buffer. A buffer can contain shell code both before and after a heredoc, and may contain several heredocs with different payload languages. The longer-term model should therefore investigate region-aware behaviour where the relevant tool supports it. Where a tool cannot safely respect regions, an explicit conservative isolation or opt-out may be safer than allowing it to process arbitrary payload as shell.

Unknown payloads must not be silently treated as shell merely because the enclosing buffer is a shell file. Keeping an unknown body opaque is the safe fallback direction under the adopted lexical-zone policy; the exact user-visible presentation of that opaque region remains to be designed.

## Relationship to current architecture and tests

The design contract now makes the Return-local bounded-scope decision explicit. This note expands the rationale for future embedded-language work; it does not authorise rebuilding a global heredoc model or claim that embedded-language integrations exist.

Current mini.pairs and Blink tests demonstrate coexistence in the managed body, not payload-language isolation. The inspected controls for those plugins are buffer-wide; no region-scoped disable API was established. Do not disable them buffer-wide merely because a buffer contains a heredoc.

Current Conform/shfmt tests establish preservation for selected shell fixtures, not arbitrary Markdown, JSON, YAML, templates, or other embedded payloads. Do not generalise those results.

The scanner should continue to report structural regions and confidence. Language identification and editor-tool policy should be layered consumers of that information, not reasons to weaken conservative structural recognition.

## Broader embedded-language presentation direction

Future syntax-presentation work should be considered as a general embedded-language capability, not only as a fix for Bash heredoc body highlighting. Tree-sitter injections are a possible mechanism for presenting embedded payloads such as Python, Rust, Markdown/markup, and other languages where the surrounding document has a different filetype. The same separation remains essential across these cases: the host document or plugin establishes the authoritative region; language classification selects a parser when sufficiently grounded; presentation consumes the region; and unknown content remains opaque. Injection does not, by itself, establish host-language lexical boundaries or guarantee region-aware diagnostics, completion, linting, LSP, or formatting.

Parse-tree boundary analysis, query-capture inspection, parser/API compatibility checks, and injection lifecycle design belong to that future investigation. They are not prerequisites for the current heredoc scanner/editing/shell-delivery/formatter work and should not be treated as its immediate next step.

## Open questions for future investigation

These are deliberately unresolved:

- Which editing and language-service integrations can reliably respect the established lexical-zone boundary for every supported heredoc body? The boundary itself is adopted policy; the scope and implementation details of individual tool integrations remain to be investigated.
- Which existing declaration conventions should be recognised initially, and what exact syntax/position/precedence rules apply to each? In particular, how should shebangs and modelines be detected without confusing buffer-level filetype with per-region language identity?
- How should explicitly associated filename/path metadata be represented and maintained for an individual payload region?
- What narrow fallback, if any, is appropriate for payload formats without a natural declaration, and how will its editor-metadata versus delivered-content semantics be made explicit?
- How should conflicting or malformed declarations be handled? The conservative default is unknown/opaque rather than heuristic guessing.
- Which Neovim/Tree-sitter APIs can consume scanner-derived ranges and region-specific language associations robustly as the buffer changes?
- Which diagnostics, completion, LSP, lint, and formatter integrations can actually scope behaviour to a region rather than a whole buffer?
- How should formatting be handled when a formatter cannot exclude heredoc payloads? Should formatting be skipped, selectively delegated, or made explicitly user-controlled?
- How should nested or multiple heredocs with different payload languages be represented and tested?
- What is the appropriate minimum Neovim and plugin API support for any such integration?

## Guidance for the next session

Treat this as future-development context, not a task already authorised for implementation. First inspect the current scanner/region interface, current design contract, and installed integration APIs. Separate observed capabilities from proposals. Do not infer that Tree-sitter injection alone solves diagnostics, completion, linting, or formatting. Any implementation proposal should identify its structural source of truth, region scope, unknown-language fallback, mutation risks, and regression tests before changing behaviour.

Related documents: [design contract](design.md), [scanner interface](scanner.md), [plugin compatibility inventory](plugin-compatibility.md), and [CI design](ci.md).
