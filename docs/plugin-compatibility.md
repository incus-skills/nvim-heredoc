# Local LazyVim compatibility inventory

The plugin must coexist with the actual LazyVim and plugin revisions installed by the user. Do not infer buffer-local control names from examples or from a different release.

Run the inventory from the repository root on the target Neovim installation:

\`\`\`sh
bash tests/diagnostics/inspect-lazyvim.sh
\`\`\`

It reports:

- Neovim runtime version;
- installed Git revisions for LazyVim, \`mini.pairs\`, \`blink.cmp\`, \`conform.nvim\`, \`lazy.nvim\`, and Treesitter;
- matching entries in \`lazy-lock.json\`;
- relevant local configuration lines for shell filetypes;
- candidate buffer-local controls found in the installed plugin Lua source.

Review the output before sharing it. It can reveal local configuration details. The script is diagnostic only: it does not change the user's Neovim configuration or plugin installation.

## Compatibility boundary

The current plugin integration does not disable or override auto-pairs, completion, indentation, or formatting. Do not add buffer-local suppression until the exact installed API has been identified and verified against the installed revision.

In particular:

- Do not assume a buffer variable exists because it appears in an online example.
- Do not globally disable completion.
- Keep the shared scanner as the region authority.
- Test any integration only inside a confidently recognised managed heredoc region.
- Preserve the user's existing configuration outside that region.
- Keep Zsh out of the \`shfmt\` formatter assignment.
