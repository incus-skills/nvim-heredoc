# Local LazyVim compatibility inventory

The plugin must coexist with the actual LazyVim and plugin revisions installed by the user. Do not infer buffer-local control names from examples or from a different release.

Run the inventory from the repository root on the target Neovim installation:

```sh
bash tests/diagnostics/inspect-lazyvim.sh
```

It reports:

- Neovim runtime version;
- installed Git revisions for LazyVim, `mini.pairs`, `blink.cmp`, `conform.nvim`, `lazy.nvim`, and Treesitter;
- matching entries in `lazy-lock.json`;
- relevant local configuration lines for shell filetypes;
- candidate buffer-local controls found in the installed plugin Lua source.

Review the output before sharing it. It can reveal local configuration details. The script is diagnostic only: it does not change the user's Neovim configuration or plugin installation.

## Observed target environment (2026-11-12)

The supplied inventory reported:

| Component | Runtime / revision |
|---|---|
| Neovim | 0.12.4 |
| LazyVim | `0fa4a847929fc6beae40a3063615a58115678c34` |
| mini.pairs | `03eb1f0062a2cee5314d1ac3939246e4bb21352e` |
| blink.cmp | `78336bc89ee5365633bcf754d93df01678b5c08f` |
| conform.nvim | `016802de402556da54c36bd7359b441266b01cdd` |
| lazy.nvim | `85c7ff3711b730b4030d03144f6db6375044ae82` |
| nvim-treesitter | `19bdfc04f40ed2ccb3340591d125f759b0406875` |

These are a snapshot of one installed environment, not yet a declared support matrix. The existing Neovim 0.9.5 buffer-test job remains a separate compatibility baseline.

The local shell ftplugins reported by the inventory are the previous heredoc implementation being replaced. They are historical evidence for migration and behaviour review, not dependencies of the new plugin. A clean integration fixture must not load those files.

## Verified plugin controls at the observed revisions

The relevant source was inspected at the exact reported revisions:

- **mini.pairs** (`nvim-mini/mini.pairs`): supports global `vim.g.minipairs_disable = true` and buffer-local `vim.b.minipairs_disable = true`. Its documentation explicitly says the module does not provide filetype-dependent behaviour; buffer-level disabling is available. LazyVim's observed `coding.lua` configures its default mappings through `LazyVim.mini.pairs(opts)`. No region-aware control is provided by mini.pairs itself.
- **blink.cmp**: its `enabled()` implementation checks `vim.b.completion == false` to disable completion for the current buffer, and `true` to explicitly enable it. Its configuration also has an `enabled` callback. The buffer variable is buffer-wide, not heredoc-region scoped. LazyVim's observed blink extra configures completion and auto-bracket behaviour.
- **conform.nvim**: `format_on_save` accepts a callback that can return no format options for a particular buffer. This is a configuration-time per-buffer gate, not a discovered buffer-local disable variable. The supplied local configuration inventory showed `shfmt` assigned to Bash, `sh`, and Zsh, but did not establish that `format_on_save` is enabled. Do not assume save-time formatting is active.
- **nvim-treesitter**: parser availability was reported for Bash, `sh`, and Zsh. It remains optional and is not the region authority.

The mini.pairs and blink controls are not interchangeable: both are buffer-wide switches. Do not apply them merely because a buffer contains a managed heredoc. A future region-scoped adapter would need to preserve normal behaviour elsewhere in the same buffer and must be justified by an observed conflict.

## Compatibility boundary

The current plugin integration does not disable or override auto-pairs, completion, indentation, or formatting. Do not add buffer-local suppression until the exact installed API has been identified and verified against the installed revision.

In particular:

- Do not assume a buffer variable exists because it appears in an online example.
- Do not globally disable completion.
- Do not disable a buffer-wide feature merely because one region is a heredoc.
- Keep the shared scanner as the region authority.
- Test any integration only inside a confidently recognised managed heredoc region.
- Preserve the user's existing configuration outside that region.
- Keep Zsh out of the `shfmt` formatter assignment.

## Integration fixture requirements

The pinned fixture should use the observed versions above as an initial reproducible target, while keeping the test independent of the user's personal Neovim configuration.

- Do not copy the legacy `after/ftplugin/bash.lua`, `sh.lua`, or `zsh.lua` files into the fixture.
- Load the checked-out `nvim-heredoc` source, not a separately installed moving copy.
- Exercise mini.pairs and blink.cmp with their normal LazyVim-derived configuration enabled before considering any suppression.
- Exercise mini.pairs by sending an actual insert-mode quote keystroke in ordinary shell code and in a managed heredoc body; verify pair insertion and that the heredoc changed-range callback preserves the body bytes.
- Include ordinary `<<` and here-string `<<<` cases as non-managed controls.
- Exercise Conform formatting only where the fixture explicitly configures it; assert payload bytes before and after formatting.
- Record which plugin behaviours were actually exercised. A plugin merely being installed is not evidence of coexistence.
- Keep the container job separate from the lightweight core and shell-semantic jobs.
