# Future development context: embedded heredoc payloads

**Status:** mixed: the lexical-zone boundary policy below is adopted project policy; the choice and implementation of payload presentation, language classification, and region-aware editor integrations remain future-development work.

This note records both the adopted boundary policy and the still-open design questions for embedded payload support. It is intended to survive context changes and help a fresh contributor or AI session distinguish settled requirements from unresolved implementation choices.

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

## Observed payload conventions in the user's scripts

The user's predominant heredoc use is provisioning files for installations and sending messages to the terminal. In these workflows, payload language is generally indicated by one of two contextual signals:

1. **Explicit signal — a shebang in the payload.** Provisioning heredocs may contain scripts with a shebang, which can identify the intended interpreter/language. This is analogous to the shebang-based language selection in the mise configuration.
2. **Implicit signal — the receiving command in the shell command/pipeline.** A heredoc may be supplied to a consumer that establishes how its input is interpreted or rendered. For example:

   ```sh
   cat <<'EOF' | glow -
   # Installation notes

   This is **Markdown** rendered in the terminal.
   EOF
   ```

   Here, `glow -` is the downstream consumer of standard input and provides evidence that the heredoc payload is Markdown.

These are complementary signals: a shebang describes the intended script interpreter, while a downstream consumer can describe the payload's input format or presentation. Language classification should therefore consider the complete shell command relationship, including the command receiving the heredoc and its pipeline/redirection context, rather than inspecting only the opener, delimiter, or body.

The consumer signal needs semantic knowledge of the command and its input convention. A generic command such as `cat` does not, by itself, identify a language; in the example, the useful signal is `glow -`. If the consumer is unknown, ambiguous, or does not imply a specific format, classification should remain unknown rather than guess. This is an observed usage pattern and a promising source of classification evidence, not yet an implemented rule or a complete command-to-language mapping.

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

## Open questions for future investigation

These are deliberately unresolved:

- Which editing and language-service integrations can reliably respect the established lexical-zone boundary for every supported heredoc body? The boundary itself is adopted policy; the scope and implementation details of individual tool integrations remain to be investigated.
- How should the two observed contextual signals be resolved: an explicit shebang in the payload, and an implicit language/format indication from the downstream command consuming the heredoc (including pipeline and redirection context)? What command-to-language knowledge is needed, how should conflicting signals be handled, and what confidence threshold is required?
- How should unknown or ambiguous payloads behave? Is opaque treatment the default, and how should users opt into a language?
- Which Neovim/Tree-sitter APIs can consume scanner-derived ranges robustly as the buffer changes?
- Which diagnostics, completion, LSP, lint, and formatter integrations can actually scope behaviour to a region rather than a whole buffer?
- How should formatting be handled when a formatter cannot exclude heredoc payloads? Should formatting be skipped, selectively delegated, or made explicitly user-controlled?
- How should nested or multiple heredocs with different payload languages be represented and tested?
- What is the appropriate minimum Neovim and plugin API support for any such integration?

## Guidance for the next session

Treat this as future-development context, not a task already authorised for implementation. First inspect the current scanner/region interface, current design contract, and installed integration APIs. Separate observed capabilities from proposals. Do not infer that Tree-sitter injection alone solves diagnostics, completion, linting, or formatting. Any implementation proposal should identify its structural source of truth, region scope, unknown-language fallback, mutation risks, and regression tests before changing behaviour.

Related documents: [design contract](design.md), [scanner interface](scanner.md), [plugin compatibility inventory](plugin-compatibility.md), and [CI design](ci.md).
