# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is Josh Medeski's personal Neovim configuration, written entirely in Lua. Built on kickstart.nvim with Lazy.nvim as the plugin manager. All plugins default to lazy loading (`defaults = { lazy = true }`).

## Code Style

- Lua formatted with StyLua: 160 column width, 2-space indentation, single quotes preferred, no call parentheses
- StyLua runs automatically via Claude hook on Write/Edit (see `.claude/settings.json`)
- Config: `.stylua.toml`

## Architecture

### Bootstrap Sequence (`init.lua`)

Utilities load in strict dependency order before plugins:

```
options → commands → events → keymaps → highlights → auto_commands → lazy_nvim (bootstrap) → lazy (plugin setup)
```

Leader key (`<space>`) **must** be set in `options.lua` before Lazy.nvim loads plugins.

### Directory Layout

- `lua/utils/` - Core configuration (options, keymaps, autocommands, commands, highlights, icons, events)
- `lua/plugins/` - One file per plugin, auto-discovered by Lazy.nvim via `require('lazy').setup({ import = 'plugins' })`
- `lua/kickstart/` - Upstream kickstart.nvim modules (health checks)

### Plugin File Convention

Each plugin file in `lua/plugins/` returns a single table (or list of tables):

```lua
return {
  'author/plugin-name',
  event = 'VeryLazy',        -- lazy load trigger
  dependencies = { ... },
  keys = { ... },             -- keybindings (also triggers lazy load)
  opts = { ... },             -- passed to plugin setup()
  config = function() end,    -- custom setup when opts isn't enough
}
```

Keybindings are defined per-plugin via `keys` tables (for which-key integration) and globally in `utils/keymaps.lua`.

### Key Subsystems

- **LSP**: `plugins/lspconfig.lua` - Mason auto-installs servers; supports 25+ language servers
- **Completion**: `plugins/blink.lua` - Sources: LSP, git, path, snippets, buffer, emoji, AI
- **Formatting**: `plugins/conform.lua` - Format-on-save with per-language formatters (prettier, stylua, biome, black, gofumpt)
- **Treesitter**: `plugins/treesitter.lua` - Auto-install parsers
- **Fuzzy finding**: `plugins/snacks.lua` and `plugins/telescope.lua`
- **Git**: neogit, gitsigns, diffview, gitlinker, octo
- **AI**: codecompanion (multi-model), copilot, MCP hub integration
- **Debug**: `plugins/dap.lua` - DAP with Go support via delve
- **Testing**: `plugins/neotest.lua` - Go, Playwright, Vitest runners

### Notable Preferences

- No line numbers (number and relativenumber both off)
- Hidden statusline (`laststatus = 0`)
- Hidden tabline (`showtabline = 0`)
- 2-space indentation with smart indent
- Clipboard not synced to OS by default (`clipboard = ''`)
- Catppuccin theme with auto dark/light switching via dark-notify
- Persistent undo in `~/.local/state/nvim/undo`
