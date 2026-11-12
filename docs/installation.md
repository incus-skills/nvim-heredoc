# Installation and replacement

This is the initial user-facing installation path for the tested Lua implementation. It targets LazyVim/lazy.nvim and deliberately keeps the implementation in this repository; there is no generated copy of the Lua modules and no separate installer implementation.

## 1. Preserve and disable the previous ftplugins

The previous implementation is expected to be in:

- `after/ftplugin/bash.lua`
- `after/ftplugin/sh.lua`
- `after/ftplugin/zsh.lua`

Inspect these files first. If they contain unrelated filetype configuration, separate that configuration before moving the files. Do not overwrite or discard unrelated settings.

For files that contain only the previous heredoc implementation, move them into a timestamped backup:

```sh
config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
backup="$config/backup/nvim-heredoc-legacy-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$backup/after/ftplugin"
for ft in bash sh zsh; do
  old="$config/after/ftplugin/$ft.lua"
  if [ -f "$old" ]; then
    mv -- "$old" "$backup/after/ftplugin/$ft.lua"
  fi
done

printf 'Legacy ftplugins backed up under: %s\n' "$backup"
```

Keep the printed backup path. Moving these files out of `after/ftplugin` prevents the old and new implementations from both editing the same buffer. The backup makes this step reversible.

## 2. Add the plugin to LazyVim

Create `lua/plugins/nvim-heredoc.lua` in your Neovim configuration:

```lua
return {
  {
    "incus-skills/nvim-heredoc",
    lazy = false,
  },
}
```

If you already have a file with this name, merge the plugin specification into it rather than replacing your existing configuration.

Using `lazy = false` loads the small `plugin/nvim-heredoc.lua` entrypoint at startup. That entrypoint calls `require("nvim-heredoc").setup()`, which registers the Bash, POSIX `sh`, and Zsh buffer integration. No additional `config = function()` is required.

Then run `:Lazy sync` and restart Neovim.

### Using a local checkout instead

For development against a working tree, use a local directory specification instead of the GitHub string:

```lua
return {
  {
    dir = vim.fn.expand("~/src/nvim-heredoc"),
    name = "nvim-heredoc",
    lazy = false,
  },
}
```

Replace the example path with the actual repository checkout. Do not declare both specifications at once.

## 3. Confirm that the replacement loaded

After restarting Neovim, run:

```vim
:lua print(vim.g.loaded_nvim_heredoc)
:lua print(package.loaded["nvim-heredoc"] ~= nil)
```

Both should print `true`. Open a `.bash`, `.sh`, or `.zsh` file and confirm its filetype is respectively `bash`, `sh`, or `zsh`:

```vim
:set filetype?
```

The plugin does not change the user's completion, pair, indentation, or formatter settings. It does not assign Zsh to `shfmt`.

## 4. Exercise the live editing path

Use a disposable `.bash` file. Type the following structure using literal TAB characters before the `cat` command and the closing delimiter:

```bash
if true; then
<TAB>cat <<-EOF
<TAB>  payload with two leading spaces
<TAB>EOF
fi
```

For an automatic-closer check, start with only the first two lines and leave insert mode. A safely recognised incomplete `<<-` opener should receive a matching closer using the opener's structural TAB prefix.

For a changed-range check, paste several body lines before the closer, including an empty line and a line beginning with spaces. The plugin should add the structural TAB prefix where needed without removing or changing the payload spaces. Repeated edits should not duplicate the prefix.

Finally, execute the disposable script with Bash and inspect the delivered output. For example:

```sh
bash /path/to/heredoc-live-test.bash
```

Remember that `<<-` strips leading TAB bytes from body lines at shell execution. It preserves leading spaces. This shell-delivery check matters: a visually indented buffer alone does not prove that the shell receives the intended payload.

Also confirm that an ordinary `<<` heredoc in the same file remains unchanged. If any result is surprising, capture the buffer contents with visible whitespace (for example `:set list`) and report the Neovim messages before changing configuration.

## 5. Roll back

1. Remove the `nvim-heredoc` plugin specification (or remove only its entry if it was merged into an existing file).
2. Restore the backed-up ftplugins to their original paths. Use the exact backup path printed during installation:

   ```sh
   config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
   backup="$config/backup/nvim-heredoc-legacy-YYYYMMDD-HHMMSS"
   mkdir -p "$config/after/ftplugin"
   for ft in bash sh zsh; do
     old="$backup/after/ftplugin/$ft.lua"
     if [ -f "$old" ]; then
       mv -- "$old" "$config/after/ftplugin/$ft.lua"
     fi
   done
   ```

3. Run `:Lazy clean` if you also want lazy.nvim to remove the now-unreferenced plugin checkout.
4. Restart Neovim.

Do not run the rollback restore over files that have since been recreated; compare them first.

## Current verification boundary

The repository's CI exercises the shared scanner, Neovim buffer integration, shell payload delivery, formatter behaviour, and a pinned LazyVim/plugin fixture. The fixture is not the user's full configuration and is not a substitute for the live check above. The first local installation is therefore a validation step, not a claim that every shell grammar case or every personal LazyVim override is supported.

The Lua scanner remains deliberately conservative. Backtick substitutions, heredoc redirections inside command substitutions, multiline quoted commands, and other uncertain constructs are not safe editing targets. See [the scanner limits](scanner.md).
