# nvim-initmd

A small Markdown-driven Neovim bootstrap using Neovim's built-in `vim.pack`.
Plugin specs, executable setup code, and readable notes can live together in
`~/.config/nvim/init.md`.

## Requirements

- Neovim 0.12 or newer (`vim.pack`)
- Git

## Install

Clone this repository, then run:

```sh
./setup-init-md.sh
nvim
```

The installer copies the bootstrap and parser modules into
`~/.config/nvim/init-modules/` and installs the bootstrap as `init.lua`. It
copies `nvim-config-template.md` to `~/.config/nvim/init.md` only when there is
no existing config, so an existing personal config is not overwritten.

## Markdown format

`**Spec:**` code blocks contain Lua that returns one plugin spec or a list of
specs. The parser collects these values and generates a call to
`vim.pack.add(specs)`. `return` belongs to this Markdown adapter format; it is
not part of Neovim's `vim.pack` API. Native `vim.pack.add()` accepts a list of
spec tables, for example:

```lua
vim.pack.add({
  { src = "https://github.com/folke/which-key.nvim" },
})
```

For consistency with the API, prefer a returned list in Markdown, even for
one plugin:

````markdown
**Spec:**
```lua
return {
  { src = "https://github.com/folke/which-key.nvim" },
}
```
````

`**Setup: executable**` marks code the bootstrap runs after adding the plugin
specs. Other `**Setup:**` examples are documentation only; they are never
executed implicitly. This explicit boundary prevents prose examples from
becoming startup code.

The parser can extract ordinary lazy.nvim shorthand specs such as
`{ "owner/repo", opts = ... }` into `vim.pack` source specs. That extraction is
not a complete automatic migration of lazy.nvim behavior: callbacks,
dependencies, triggers, and setup ordering must be reviewed and represented as
supported `vim.pack` specs or explicit executable setup blocks.

## Validate and test

```sh
./scripts/test-pack-config.sh
./scripts/test-installer.sh
```

The isolated test uses the public template by default. It checks parser edge
cases, plugin installation, main config execution, and that executable setup
blocks report no errors. To test a separate Markdown file:

```sh
NVIM_PACK_MD=/absolute/path/to/init.md ./scripts/test-pack-config.sh
```

## Local privacy

Personal configs, local notes, backups, and experiments belong in the ignored
`context/` directory. Only the installer/runtime, public template, tests, and
this README are intended to be tracked in this minimal repository.
