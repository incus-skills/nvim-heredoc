# Installation

## lazy.nvim

Add the plugin to your lazy.nvim plugin specifications:

```lua
{
  "incus-skills/nvim-heredoc",
  ft = { "bash", "sh", "zsh" },
  opts = {},
}
```

lazy.nvim loads the plugin when the first supported filetype is detected and
calls `require("nvim-heredoc").setup({})`. The plugin attaches to matching
buffers through its `FileType` autocmd.

No generated `after/ftplugin` files, copied Lua modules, shell provisioner, or
manual `runtimepath` changes are required. The repository checkout and the
plugin manager own their respective installation and update lifecycles.

## Configuration

There are currently no user-facing setup options. The supported filetypes are
Bash (`bash`), POSIX shell (`sh`), and Zsh (`zsh`); they are part of the
plugin's current support contract.

No special buffer indentation settings are required. The plugin leaves the
buffer's existing `expandtab`, `tabstop`, `softtabstop`, and `shiftwidth` values
unchanged. Those options were previously forced by the development provisioner
as a workaround for an older implementation that needed to position the opener
at column zero; that workaround is obsolete. The current implementation
preserves the opener's position without requiring those settings. It uses
literal TAB bytes where shell `<<-` semantics require them.

## Verify

After lazy.nvim has installed the plugin, open a Bash, POSIX `sh`, or Zsh
buffer and check the attachment marker:

```vim
:set filetype?
:lua print(vim.b.nvim_heredoc_attached)
```

The marker should print `true` for a supported filetype.

Use a disposable shell file to check closer insertion and changed-range
handling:

```bash
if true; then
<TAB>cat <<-EOF
<TAB>  payload with two leading spaces
<TAB>EOF
fi
```

The structural prefixes shown as `<TAB>` must be literal TAB characters. The
plugin should add the structural TAB prefix where needed without removing or
changing payload spaces. Repeated edits should not duplicate the prefix.

Also confirm that an ordinary `<<` heredoc remains unchanged. Execute the
disposable script with Bash and inspect the delivered output:

```sh
bash /path/to/heredoc-live-test.bash
```

For `<<-`, the shell strips leading TAB bytes from body lines and the
terminator; it preserves leading spaces. A visually indented buffer is not
sufficient evidence that the shell receives the intended payload.

If anything is unexpected, capture the buffer with visible whitespace (for
example `:set list`) and collect `:messages` before changing other
configuration.

## Validation boundary

CI exercises the shared scanner, Neovim buffer integration, shell payload
delivery, formatter behaviour, and a pinned LazyVim/plugin coexistence fixture.
The LazyVim fixture uses the repository checkout through lazy.nvim's local
`dir` specification and the same `ft` and `opts` loading contract as the
installation example. It is a controlled integration environment, not the
user's complete configuration and not a substitute for live verification in
the target environment.

The Lua scanner remains deliberately conservative. Backtick substitutions,
heredoc redirections inside command substitutions, multiline quoted commands,
and other uncertain constructs are not safe editing targets. See the scanner
limits in [the design contract](design.md).
