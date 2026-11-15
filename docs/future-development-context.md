# Future development context: embedded heredoc payloads

**Status:** exploratory design context; not an implementation commitment or a change to the current release contract.

This note records a development concern raised while considering what happens inside a managed heredoc body. It is intended to survive context changes and help a fresh contributor or AI session resume the discussion without treating an open question as an established requirement.

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

## Architectural distinction to preserve

The existing project decision is that the shared lexical scanner is the authority for structural heredoc regions. Future embedded-language work should preserve that authority while keeping these questions separate:

1. **Structural recognition — where is the payload?**  
   The scanner identifies the opener, body, terminator, queue position, and confidence/ambiguity. This is the boundary information that editor integrations should consume. Do not create independent heredoc-boundary heuristics in each integration.

2. **Payload classification — what is the payload language?**  
   A body may be identified as a known language, inferred with some confidence, or remain unknown/opaque. Structural recognition must not depend on successful language classification.

3. **Presentation — how is the payload parsed and highlighted?**  
   Tree-sitter injections are one possible consumer of the scanner's body ranges. They should not become a replacement authority for shell heredoc structure, especially in incomplete editing buffers.

4. **Language services — which tools may operate in the region?**  
   Diagnostics, completion, LSP features, linting, and related services need their own region-aware integration. Availability of an embedded parser or language server is not proof that requests and diagnostics are scoped correctly.

5. **Mutation policy — which tools may rewrite the payload?**  
   Formatters and other mutating tools need particular care. A tool appropriate for the surrounding shell source may be inappropriate for the body. Any future formatter integration must preserve payload semantics and bytes according to an explicit policy, with tests for the actual tool and configuration.

The desired direction is not necessarily to disable every shell feature for an entire buffer. A buffer can contain shell code both before and after a heredoc, and may contain several heredocs with different payload languages. The longer-term model should therefore investigate region-aware behaviour where the relevant tool supports it. Where a tool cannot safely respect regions, an explicit conservative isolation or opt-out may be safer than allowing it to process arbitrary payload as shell.

Unknown payloads should not be silently treated as shell merely because the enclosing buffer is a shell file. Keeping an unknown body opaque is a candidate safe fallback; its exact user-visible behaviour remains to be designed.

## Relationship to current architecture and tests

The existing design contract already requires integrations to consume the shared region model and says future embedded-language support should be preserved. This note expands the rationale and identifies the separate layers that would need investigation; it does not change the scanner's current responsibility or claim that those integrations exist.

Current mini.pairs and Blink tests demonstrate coexistence in the managed body, not payload-language isolation. The inspected controls for those plugins are buffer-wide; no region-scoped disable API was established. Do not disable them buffer-wide merely because a buffer contains a heredoc.

Current Conform/shfmt tests establish preservation for selected shell fixtures, not arbitrary Markdown, JSON, YAML, templates, or other embedded payloads. Do not generalise those results.

The scanner should continue to report structural regions and confidence. Language identification and editor-tool policy should be layered consumers of that information, not reasons to weaken conservative structural recognition.

## Open questions for future investigation

These are deliberately unresolved:

- Should editor-tool isolation apply to every managed `<<-` body, or only to a subset? The working recommendation raised in discussion was to treat all managed bodies as payload regions regardless of delimiter quoting: delimiter quoting controls shell expansion at execution time, not whether the editor should assume the body is shell code. This has not yet been confirmed as a project decision.
- What language-identification signals are appropriate for heredoc bodies: explicit user configuration, delimiter conventions, shebangs or content inspection, filetype conventions, or a combination? What confidence threshold is required?
- How should unknown or ambiguous payloads behave? Is opaque treatment the default, and how should users opt into a language?
- Which Neovim/Tree-sitter APIs can consume scanner-derived ranges robustly as the buffer changes?
- Which diagnostics, completion, LSP, lint, and formatter integrations can actually scope behaviour to a region rather than a whole buffer?
- How should formatting be handled when a formatter cannot exclude heredoc payloads? Should formatting be skipped, selectively delegated, or made explicitly user-controlled?
- How should nested or multiple heredocs with different payload languages be represented and tested?
- What is the appropriate minimum Neovim and plugin API support for any such integration?

## Guidance for the next session

Treat this as future-development context, not a task already authorised for implementation. First inspect the current scanner/region interface, current design contract, and installed integration APIs. Separate observed capabilities from proposals. Do not infer that Tree-sitter injection alone solves diagnostics, completion, linting, or formatting. Any implementation proposal should identify its structural source of truth, region scope, unknown-language fallback, mutation risks, and regression tests before changing behaviour.

Related documents: [design contract](design.md), [scanner interface](scanner.md), [plugin compatibility inventory](plugin-compatibility.md), and [CI design](ci.md).
