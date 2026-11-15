# Issue 001 — Function-wrapped heredoc boundary is not preserved during insertion

**Status:** open — investigation ongoing  
**Priority:** high — source corruption during ordinary editing  
**Area:** interactive editing, region recognition, function boundaries  
**Record type:** provisional repository-native Markdown issue; not a commitment to GitHub Issues or git-native-issue

## Problem

When inserting a new <<- heredoc inside a shell function immediately before an existing function containing a completed heredoc, the new heredoc can absorb the following function and its heredoc. The existing heredoc's EOF is then treated as the new heredoc's terminator, and the existing function is indented or otherwise rewritten as payload.

The user's observed starting content is:

~~~bash
conf_print_test1() {
  cat <<'EOF'
hello1
 hello2
  hello3
hello4
EOF
}
~~~

The user begins a new function above it. The function opener's auto-pairing inserts }. They type:

~~~bash
conf_print_test2() {
  cat <<-'EOF'
~~~

After Return, the new body line is indented, but a new closing delimiter is not inserted before the auto-paired }. Subsequent processing treats the existing function and heredoc as part of the new heredoc body. The existing EOF is adopted as the new terminator.

A representative corrupted result observed by the user:

~~~bash
conf_print_test2() {
  cat <<-'EOF'
		
		}
		
		conf_print_test1() {
		  cat <<'EOF'
		hello1
		 hello2
		  hello3
		hello4
EOF
}
~~~

The user has identified two related cases: function-wrapped heredocs and plain heredocs. This issue currently investigates the function-wrapped case first.

## Expected behaviour and constraints

- The auto-paired function-closing } is a known pending function boundary.
- A newly opened heredoc inside that function must receive its closer before the }.
- The } remains shell syntax outside the heredoc body.
- If the user deliberately deletes the } before continuing, that boundary is withdrawn. The editor must not impose a function boundary that no longer exists; following text may then intentionally become heredoc payload.
- A completed pre-existing heredoc must remain protected from being adopted as the new heredoc's terminator.
- Existing managed heredocs must retain their known boundaries; edits should affect only their actual body.
- The payload's existing whitespace and bytes must not be normalised or rewritten.
- Ordinary << heredocs and here-strings <<< remain outside the managed editing scope.

## Investigation history

### Cycle 1 — Separate existing-heredoc protection from the function boundary

**Trigger:** The new opener was adopting the old completed heredoc's terminator, while the auto-paired function brace was being treated as body text.

**Reasoning:** Two distinct boundary questions are involved and should not be conflated:

1. Is there a pre-existing completed heredoc inside what the new opener would otherwise consume?
2. Is there a still-present function-closing brace that bounds the new heredoc?

The first can apply to plain and function-wrapped heredocs. The second is specific to function-wrapped insertion.

**Implementation exploration:** The scanner's heredoc records were extended with opener_text so an earlier opener can be compared with a candidate region. A preservation heuristic was added to inspect the previous/current region state, identify a matching existing opener, and look for a standalone function-closing brace between the new body and the old opener. The function-header recogniser was adjusted to accept the user's name() { form.

**Relevant implementation commits:**
- a4b15f5d44bbb3ec9bf29c3c9c24e4763ac848fe — retain original opener text in scanner records.
- 61dabfbed4bbe955b2fd587fc06d277b9f91469f — initial existing-heredoc/function-boundary preservation heuristic.
- 4b857a34bffb353fee2de9b780f2a5a72c4fe8e8, 60f8fedadadbf6f78f62b5caac6430c801358634, e26bc071cc1373235e90fde344139446b2a10942 — successive boundary and recogniser test/fix attempts.
- 8a198d465ea724ca41c4cd311e0074c562a80a3 — latest implementation-side fix in this sequence, intended to protect inserted heredocs before transition reconciliation.

**Evidence:** An earlier synthetic buffer test/CI sequence did not reliably reproduce the user's interactive behaviour. The user updated the plugin locally and reported no change. This established that passing synthetic tests was insufficient evidence for the actual Insert-mode path.

**Interpretation:** The two boundary mechanisms remain complementary. The heuristic implementation is not established as correct by the synthetic tests.

### Cycle 2 — Exercise the real Insert-mode and MiniPairs path

**Trigger:** The previous test harness did not model the user's actual sequence: creating a function with auto-pairing, pressing Return inside the pair, typing a heredoc opener, and allowing live buffer-change processing to run.

**Reasoning:** A useful regression must use Neovim's input loop and the actual MiniPairs integration, rather than directly constructing the expected buffer or calling the region processor. The test must also prove that the original function and heredoc remain byte-for-byte intact.

**Test changes:** tests/lua/live_insert_spec.lua gained a function-boundary scenario, enabled by NVIM_HEREDOC_FUNCTION_BOUNDARY=1. tests/run-lazyvim.sh runs it in the pinned LazyVim integration environment. The scenario:
1. Starts with the existing completed function/heredoc in the buffer.
2. Opens a line above it using Insert mode.
3. Types conf_print_test2() { and asserts that real MiniPairs input creates {}.
4. Sends Return through Neovim's input loop and checks the brace is on its own line.
5. Types the new cat <<-'EOF' opener.
6. Waits for scheduled live processing and asserts the new closer appears before }.
7. Enters the body, types payload, leaves Insert mode, and verifies the original function remains unchanged.

**Evidence:** GitHub Actions run [43737316655](https://github.com/incus-skills/nvim-heredoc/actions/runs/43737316655) passed the pinned LazyVim/plugin coexistence job, including this live function-boundary test.

**Evidence limitation:** This demonstrates that the test scenario passes in the CI environment with its pinned MiniPairs setup. It does not establish that the user's interactive configuration now behaves correctly. The user's earlier local report of no change remains unresolved. The test also does not yet exercise the deliberate deletion of } before continuing.

## Current understanding

### Supported by current evidence

- The failure involves both the treatment of a pre-existing completed heredoc and the boundary of the newly opened function-wrapped heredoc.
- Existing-heredoc protection and function-brace boundary handling are separate responsibilities.
- A MiniPairs-backed Neovim input-loop test now exists and passes in the pinned CI environment.
- Synthetic buffer tests alone did not establish that the user's interactive editing sequence was fixed.

### Not yet established

- Whether the current implementation reliably inserts the closer before the brace in the user's actual Neovim configuration.
- Whether the implementation correctly withdraws the function boundary when the user deletes the auto-paired }.
- Whether the existing-heredoc protection behaves correctly for the corresponding plain-heredoc case.
- Whether the current heuristic handles nested functions, multiple braces, comments, or other shell constructs safely.

## Next testing cycle

**Objective:** Validate the function-boundary behaviour in both branches of the user's editing intent before changing the implementation again.

**Required test cases:**

1. **Brace retained:** reproduce the user's exact insertion sequence with MiniPairs active. Confirm that the new closer is inserted before }, the body is editable, and the old function/heredoc remains byte-identical.
2. **Brace deliberately deleted:** delete the auto-paired } before continuing. Confirm that the plugin does not invent or retain a function boundary and that subsequent text is treated according to the remaining heredoc structure.
3. **Existing-heredoc integrity:** in both cases, compare the original function's lines byte-for-byte and report any mutation.
4. **Interactive verification:** after the CI regression passes, have the user repeat the sequence in their installed configuration. Record this separately from CI evidence.

**Do not:** treat a passing CI test as proof of the user's local fix; alter implementation merely to satisfy a synthetic expected buffer; or broaden this cycle into the plain-heredoc case before the function-wrapped behaviour is understood.

## Cycle result template

For each subsequent cycle, append a dated entry containing:

- **Trigger:** what observation or previous result initiated the cycle.
- **Reasoning:** why this test or change is the next discriminating step.
- **Hypothesis:** what behaviour is expected and what alternative it distinguishes.
- **Test design:** exact interaction sequence and assertions.
- **Changes:** files and commits changed, if any.
- **Evidence:** synthetic, headless Neovim, CI, and user's interactive observations reported separately.
- **Interpretation:** what is supported, rejected, or still uncertain.
- **Handoff:** the next action and assumptions the next session must avoid.

Do not overwrite earlier cycle results when later evidence changes the interpretation. Append a new cycle and explicitly reconcile the difference.
