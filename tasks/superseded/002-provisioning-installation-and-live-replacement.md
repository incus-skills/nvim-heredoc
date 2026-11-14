# Task 002 — Provisioning installation and live replacement

**Status:** superseded — 2026-11-14  
**Disposition:** replaced by the conventional lazy.nvim plugin architecture  
**Original scope:** provision the shared Lua implementation through generated `after/ftplugin` files and verify replacement in the live Neovim configuration.

## Why this task was superseded

The installation decision changed: the repository is now distributed and loaded as a normal Neovim plugin. lazy.nvim is the documented installation path, and the repository's pinned LazyVim integration fixture exercises that same plugin-manager loading lifecycle.

The former provisioner, its installer test, and its CI step were removed. The plugin is no longer copied into user configuration, and generated `after/ftplugin` shims are no longer part of the installation or validation model. The original acceptance criteria therefore no longer describe the intended product and must not remain active work.

## Replacement and validation

- Stage 1 established normal lazy.nvim loading through the documented `ft` and `opts` specification.
- Stage 2 removed the legacy shell provisioner and installer test, and updated installation, design, and CI documentation.
- The setup path no longer changes `expandtab`, `tabstop`, `softtabstop`, or `shiftwidth`. Those forced values were an obsolete workaround for the earlier opener-positioning implementation.
- The buffer regression test verifies column-zero opener placement, body TAB insertion, and closer alignment with non-default buffer indentation options left unchanged.
- GitHub Actions run [43641487196](https://github.com/incus-skills/nvim-heredoc/actions/runs/43641487196) passed all five validation jobs for commit `e78df65a64446c366131c6e3d9d2bcb4ca742206`.

## Verification boundary

The CI result establishes the tested lazy.nvim loading path and the five repository validation layers. It does not claim that the plugin has been installed or live-tested in the user's workstation configuration. Any future workstation verification should use the plugin-manager installation path, not revive the retired provisioner.

The original provisioning objective is closed as superseded, not marked complete under its former acceptance criteria.
