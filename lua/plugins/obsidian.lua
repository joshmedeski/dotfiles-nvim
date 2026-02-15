return {
  'obsidian-nvim/obsidian.nvim',
  version = '*',
  cmd = { 'Obsidian' },
  event = {
    'BufReadPre ' .. vim.fn.expand '~' .. '/c/second-brain/*.md',
    'BufNewFile ' .. vim.fn.expand '~' .. '/c/second-brain/*.md',
  },
  ---@module 'obsidian'
  ---@type obsidian.config
  opts = {
    workspaces = {
      {
        name = 'personal',
        path = '~/c/second-brain',
      },
    },
    completion = {
      min_chars = 2,
    },

    legacy_commands = false,

    daily_notes = {
      folder = 'Days',
    },

    templates = {
      folder = 'Resources/Templates',
      date_format = '%Y-%m-%d-%a',
      time_format = '%H:%M',
    },

    follow_url_func = function(url)
      vim.fn.jobstart { 'open', url }
    end,

    open = {
      func = function(uri)
        vim.ui.open(uri, { cmd = { 'open', '-a', '/Applications/Obsidian.app' } })
      end,
    },

    ui = { enabled = false },
  },
}
