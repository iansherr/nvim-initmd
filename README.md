# Neovim Config Template

This repository provides a minimal Neovim configuration template written in Lua. It covers key areas such as Global Options, Autocommands, Colorscheme setup, and a few example plugins (like Treesitter and Dashboard). Use this as a starting point to create your own custom Neovim configuration.

## Features

- Global Options: Configures basic editor behavior including leader keys, line numbering, tab settings, clipboard, and more.

- Autocommands: Automatically triggers actions on events (e.g., formatting on save, reloading changed files).

- Colorscheme Section: Loads your preferred colorscheme with a fallback if it’s unavailable.

- Plugin Examples: Provides example configurations for popular plugins:

- Treesitter: For advanced syntax highlighting and code understanding.

- Dashboard: A startup dashboard offering quick access to common actions.

- Moonfly Colorscheme: An example colorscheme plugin.

## Repository Structure

- nvim-config-template.md: Contains the annotated configuration template with detailed explanations and code snippets.

- README.md: (This file) Provides an overview and instructions on how to use the configuration template.

- init.lua: The main configuration file that makes nvim-init.md possible.

## How to Use This Template

### 1. Clone the Repository

Clone this repository to your local machine:

```bash
git clone https://github.com/yourusername/your-neovim-config.git ~/.config/nvim
```

### 2. Review the Template

Open CONFIG_TEMPLATE.md to see the detailed configuration sections. Each section includes:

- Description: Explains what the configuration does.

- Code: The Lua code you can copy or modify for your setup. 3. Customize Your Configuration

- Global Options: Adjust basic settings like leader keys, number settings, and indentation.

- Autocommands: Modify or add autocommands to suit your workflow.

- Colorscheme: Change the preferred colorscheme.

- Plugins: Add or remove plugins based on your needs. You can use Lazy.nvim, Packer.nvim, or your preferred plugin manager.

### 3. Split the Configuration

Although this template uses a single Markdown file for demonstration, you can split your configuration into separate Lua files (e.g., options.lua, autocmds.lua, plugins.lua) and source them from your init.lua.

### 4. Further Customization

Expand the template by adding new sections such as key mappings, LSP configurations, and other custom utilities. Each section in the template includes detailed notations to guide you.

### 5. Logging & Debugging

The template uses a simple logging function that writes to a log file in your Neovim cache directory (~/.cache/nvim/plugin_manager.log). Adjust the global log level by setting \_G.LOG_LEVEL in your configuration (default is set to vim.log.levels.ERROR).

## Contributions

Contributions, suggestions, and bug reports are welcome. Feel free to open an issue or submit a pull request to improve this template.

## Inspiration

I'd been considering a single init file for quite a while, but then I saw [OXY2DEV's](https://github.com/OXY2DEV) post on Reddit about [init.md](https://www.reddit.com/r/neovim/comments/1ev675c/you_have_seen_initvim_initlua_prepare_to_see/). The thing that most appealed to me about this idea was that I could keep notes and separate configuration options in the markdown file.

My attempt at init.lua got a little out of control for several reasons.

1. I wanted it to work with more than one package manager so that if something else comes along, I had the structure to easily add it.
2. I wanted [Lazy](https://github.com/folke/lazy.nvim) to install if there was no package manager so that the init could start from scratch.
3. I've always hated forced-restarts after installs. I figured Neovim should be able to install everything in one go.
4. I've been transitioning from Homebrew to Nix on my Mac. I started this process because I found the [DietPi](https://github.com/MichaIng/DietPi) project and enjoyed its declarative setup options.
5. I kept running into edge cases where detecting fenced lua code blocks wasn't enough.
6. I like logging. Maybe too much.

This is my first public project.

## License

This project is licensed under the MIT License.
