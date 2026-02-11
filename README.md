# Josh's Neovim Configuration

A personalized Neovim configuration featuring a modular architecture and extensive plugin ecosystem.

## Configuration Structure

### Core Architecture
```
.
├── init.lua                 # Main entry point
├── lazy-lock.json          # Plugin version lockfile
├── lua/
│   ├── utils/              # Core utilities and configuration
│   │   ├── auto_commands.lua
│   │   ├── commands.lua
│   │   ├── custom_colors.lua
│   │   ├── events.lua
│   │   ├── icons.lua
│   │   ├── keymaps.lua     # Global keybindings
│   │   ├── lazy.lua        # Plugin management setup
│   │   ├── lazy_nvim.lua   # Lazy.nvim configuration
│   │   └── options.lua     # Neovim options and settings
│   ├── plugins/            # Plugin configurations
│   │   ├── [50+ plugin configs]
│   │   └── init.lua
└── README.md
```

### Core Components

#### Entry Point (`init.lua`)
- Loads utilities in dependency order
- Bootstraps plugin management via Lazy.nvim
- Minimal, focused initialization

#### Utilities (`lua/utils/`)
- **options.lua**: Comprehensive Neovim settings (leader keys, UI, search, indentation)
- **keymaps.lua**: Global keybindings and navigation shortcuts
- **lazy.lua**: Plugin management with lazy loading
- **auto_commands.lua**: Custom autocommands and events
- **commands.lua**: Custom user commands
- **custom_colors.lua**: Color scheme customizations
- **events.lua**: Event handling and callbacks
- **icons.lua**: Icon configurations for UI elements

#### Plugin Ecosystem (`lua/plugins/`)
Over 40 specialized plugins organized by category:

**AI & Code Assistance**
- `copilot.lua` / GitHub Copilot code completion
- `claudecode.lua` - Claude Code integration for seamless AI development

**Development Tools**
- `lspconfig.lua` - Language server configurations
- `conform.lua` - Code formatting
- `treesitter.lua` - Syntax highlighting and parsing
- `blink.lua` - Completion engine
- `trouble.lua` - Diagnostics and quickfix
- `refactoring.lua` - Code refactoring tools

**Git Integration**
- `neogit.lua` - Git interface
- `gitsigns.lua` - Git signs and hunks
- `diffview.lua` - Git diff viewer
- `gitlinker.lua` - Git link generation
- `octo.lua` - GitHub integration

**UI & Navigation**
- `which_key.lua` - Key binding help
- `flash.lua` - Enhanced navigation
- `oil.lua` - File explorer
- `noice.lua` - Enhanced UI
- `ufo.lua` - Folding enhancements
- `render-markdown.lua` - Markdown rendering

**Productivity**
- `obsidian.lua` - Note-taking integration
- `todo-comments.lua` - TODO highlighting
- `vim-tmux-navigator.lua` - Tmux integration
- `snacks.lua` - Utility collection

**Language Support**
- `dap.lua` - Debug adapter protocol
- `neotest.lua` - Testing framework
- `coverage.lua` - Code coverage
- `package-info.lua` - Package management
- `glsl.lua` - GLSL syntax
- `openscad.lua` - OpenSCAD support
- `caddyfile.lua` - Caddyfile syntax

**Editor Enhancements**
- `mini.lua` - Mini.nvim modules
- `boole.lua` - Boolean toggling
- `inc-rename.lua` - Incremental renaming
- `indent-o-matic.lua` - Automatic indentation
- `highlight-colors.lua` - Color highlighting
- `grug-far.lua` - Find and replace
- `key-analyzer.lua` - Key binding analysis
- `dropbar.lua` - Breadcrumb navigation

### Key Features

#### Modular Design
- Clean separation of concerns
- Utilities handle core functionality
- Plugins are self-contained and configurable
- Lazy loading for optimal performance

#### Customization Philosophy
- Leader key: `<space>`
- No line numbers or relative numbers
- Minimal UI with hidden status elements
- Spell checking enabled by default
- Smart indentation (2 spaces)
- Persistent undo history

#### Development Workflow
- Comprehensive LSP support
- Integrated debugging (DAP)
- Code formatting and linting
- Git workflow integration
- AI-assisted coding
- Testing framework support

#### Plugin Management
- Lazy.nvim for plugin management
- Automatic lazy loading
- Version pinning with `lazy-lock.json`
- Modular plugin organization

### Usage

The configuration is designed for developers who want:
- A fast, responsive editor
- Comprehensive language support
- Integrated development tools
- AI-assisted coding capabilities
- Git workflow integration
- Customizable and extensible architecture

All plugins are configured to work together seamlessly while maintaining individual functionality and customization options.

## Previously Used

Plugins that were part of this config but have since been removed:

- **[avante.nvim](https://github.com/yetone/avante.nvim)** - AI-powered code editing (replaced by codecompanion)
- **[nvim-cmp](https://github.com/hrsh7th/nvim-cmp)** - Completion engine (replaced by blink.cmp)
- **[lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)** - Statusline (removed; using hidden statusline)
- **[sidekick.nvim](https://github.com/folke/sidekick.nvim)** - CLI tool integration
- **[tiny-inline-diagnostic.nvim](https://github.com/rachartier/tiny-inline-diagnostic.nvim)** - Inline LSP diagnostics display
- **[pixel.nvim](https://github.com/bjarneo/pixel.nvim)** - Alternative colorscheme
- **[telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)** - Fuzzy finder (replaced by snacks.nvim picker)
- **[fzf-lua](https://github.com/ibhagwan/fzf-lua)** - FZF integration (replaced by snacks.nvim picker)
- **[fff.nvim](https://github.com/echasnovski/fff.nvim)** - File finder (replaced by snacks.nvim picker)
- **[codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim)** - AI code companion (replaced by Claude Code)
- **[gp.nvim](https://github.com/Robitx/gp.nvim)** - Multi-provider AI chat (replaced by Claude Code)
- **[mcphub.nvim](https://github.com/ravitemer/mcphub.nvim)** - MCP hub integration (removed with codecompanion)
- **[aider.nvim](https://github.com/joshuavial/aider.nvim)** - Aider CLI integration (replaced by Claude Code)
- **[neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim)** - File explorer (replaced by oil.nvim + snacks.nvim)
- **[codediff.nvim](https://github.com/Verf/codediff.nvim)** - Code diff viewer (replaced by diffview.nvim + gitsigns)

## Installation

### Install Neovim

This config targets the latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) and latest
['nightly'](https://github.com/neovim/neovim/releases/tag/nightly) of Neovim.
If you are experiencing issues, please make sure you have the latest versions.

### Install External Dependencies

External Requirements:
- Basic utils: `git`, `make`, `unzip`, C Compiler (`gcc`)
- [ripgrep](https://github.com/BurntSushi/ripgrep#installation)
- Clipboard tool (xclip/xsel/win32yank or other depending on the platform)
- A [Nerd Font](https://www.nerdfonts.com/): optional, provides various icons
  - if you have it set `vim.g.have_nerd_font` in `init.lua` to true
- Language Setup:
  - If you want to write Typescript, you need `npm`
  - If you want to write Golang, you will need `go`
  - etc.

### Post Installation

Start Neovim

```sh
nvim
```

That's it! Lazy will install all the plugins you have. Use `:Lazy` to view
the current plugin status. Hit `q` to close the window.
