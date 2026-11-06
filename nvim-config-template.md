# Neovim Configuration

This is a small, runnable starting point using Neovim's built-in `vim.pack`.
Copy it to `~/.config/nvim/init.md`; edit the Lua blocks to customize it.

## Core options

```lua
vim.g.mapleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.termguicolors = true
```

# Plugins

## which-key.nvim

**Spec:**
```lua
return {
  {
    src = "https://github.com/folke/which-key.nvim",
  },
}
```

**Setup: executable**
```lua
require("which-key").setup({})
```
