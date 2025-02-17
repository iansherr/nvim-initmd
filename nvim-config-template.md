# YOURNAME's Config Template

This template is designed to provide a bare‐bones setup with key areas such as Global Options, Autocommands, a Colorscheme section, and a few example plugins (Treesitter, Dashboard, and Moonfly). Use this file as a starting point for your own Neovim configuration repository.

---

## Global Options

#### Description
These settings configure Neovim’s basic behavior. They set the leader keys, enable relative line numbers, and adjust essential UI options.

<details>
  <summary>Code</summary>

```lua
-- Global Options
local vim = vim

-- Set leader keys (see :help mapleader)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Editor Options
vim.opt.number = true               -- Absolute line numbers
vim.opt.relativenumber = true       -- Relative line numbers
vim.opt.clipboard = "unnamedplus"   -- Use system clipboard
vim.opt.expandtab = true            -- Use spaces instead of tabs
vim.opt.tabstop = 2                 -- Tab stops equal 2 spaces
vim.opt.shiftwidth = 2              -- Indentation width of 2 spaces
vim.opt.smartindent = true          -- Automatic indentation

-- UI Tweaks
vim.opt.cmdheight = 0               -- Minimize command-line height for a cleaner look
```

</details>

---

## Autocommands

#### Description
This section defines autocommands to trigger actions on specific events. For example, it formats the code before saving and reloads files that change outside of Neovim.

<details>
  <summary>Code</summary>

```lua
-- Autocommands

-- Format buffer before saving (if LSP formatting is available)
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  callback = function()
    if vim.lsp.buf.format then
      vim.lsp.buf.format({ async = false })
    end
  end,
})

-- Reload file if it changes outside of Neovim (useful when editing remote files)
vim.api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
  callback = function()
    vim.cmd("checktime")
  end,
})
```

</details>

---

## Colorscheme Section

#### Description
This section loads your preferred colorscheme and falls back to a default if the preferred scheme is not available.
_For more details, see [Neovim Colorscheme Docs](https://neovim.io/doc/user/ui.html#colorscheme)._

<details>
  <summary>Code</summary>

```lua
-- Colorscheme Setup
vim.cmd [[colorscheme nightfly]]
local custom_highlight = vim.api.nvim_create_augroup("CustomHighlight", {})
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "nightfly",
  callback = function()
    vim.api.nvim_set_hl(0, "Function", { fg = "#82aaff", bold = true })
  end,
  group = custom_highlight,
})
```

</details>

---

## Plugins

Below are a few example plugin configurations. (You can expand this section with additional plugins as needed.)

### Treesitter

#### Description
Treesitter provides advanced syntax highlighting and structural understanding using tree-based parsing.
_Read more: [nvim-treesitter GitHub](https://github.com/nvim-treesitter/nvim-treesitter)_

<details>
  <summary>Code</summary>

```lua
return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",  -- Automatically update parsers on install
    opts = {
      ensure_installed = { "lua", "python", "javascript" },
      highlight = { enable = true },
      indent = { enable = true },
    },
  },
}
```

</details>

---

### Dashboard

#### Description
Dashboard-nvim creates a startup screen that appears on VimEnter, providing quick access to common actions like opening a new file or finding recent files.
_Read more: [dashboard-nvim GitHub](https://github.com/nvimdev/dashboard-nvim)_

<details>
  <summary>Code</summary>

```lua
return {
  {
    "nvimdev/dashboard-nvim",
    event = "VimEnter",
    opts = function()
      return {
        theme = "doom",  -- Choose a theme: e.g., doom, alpha, etc.
        hide = { statusline = false },
        config = {
          header = {
            "Welcome to Neovim",
            "Your custom startup screen"
          },
          center = {
            { action = "ene | startinsert", desc = "New File", key = "n" },
            { action = "Telescope find_files", desc = "Find File", key = "f" },
            { action = "Telescope oldfiles", desc = "Recent Files", key = "r" },
          },
          footer = { "Happy Coding!" },
        },
      }
    end,
  },
}
```

</details>

---

### Moonfly Colorscheme

#### Description
Moonfly is a visually appealing Neovim colorscheme inspired by the moon.
_Read more: [vim-moonfly-colors GitHub](https://github.com/bluz71/vim-moonfly-colors)_

<details>
  <summary>Code</summary>

```lua
return {
  {
    "bluz71/vim-moonfly-colors",
  },
}
```

</details>
