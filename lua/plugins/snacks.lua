---@module 'snacks'

local function get_header()
  local name = vim.fn.system 'tmux display-message -p "#S"'
  if vim.v.shell_error ~= 0 or name:match '^%s*$' then
    name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
  else
    name = name:gsub('%s+$', '')
  end

  local font_dir = vim.fn.system('figlet -I 2'):gsub('%s+$', '')
  if vim.v.shell_error ~= 0 then
    return name
  end
  local fonts = vim.fn.globpath(font_dir, '*.flf', false, true)
  if #fonts == 0 then
    return name
  end
  math.randomseed(os.time())
  local font = fonts[math.random(#fonts)]

  local figlet = vim.fn.system { 'figlet', '-w', '1000', '-f', font, name }
  if vim.v.shell_error ~= 0 then
    return name
  end

  local rainbow = { 'Rainbow1', 'Rainbow2', 'Rainbow3', 'Rainbow4', 'Rainbow5', 'Rainbow6' }
  local result = {}
  local color_idx = 1
  for char in figlet:gmatch '.' do
    if char:match '%S' then
      table.insert(result, { char, hl = rainbow[color_idx] })
      color_idx = color_idx % #rainbow + 1
    else
      table.insert(result, { char })
    end
  end
  return result
end

return {
  'folke/snacks.nvim',
  enabled = true,
  lazy = false,
  ---@type snacks.Config
  opts = {
    image = { enabled = true },
    picker = { enabled = true },
    notifier = { enabled = true },
    input = { enabled = true },
    bigfile = { enabled = true },
    zen = {
      ---@type table<string, boolean>
      toggles = {
        dim = false,
        git_signs = false,
        mini_diff_signs = false,
        diagnostics = false,
        inlay_hints = false,
      },
      ---@type table<string, boolean>
      show = {
        statusline = false,
        tabline = false,
      },
      ---@type snacks.win.Config
      win = { style = 'zen', relative = 'editor' },
      zoom = {
        toggles = {},
        show = { statusline = true, tabline = true },
        win = {
          backdrop = false,
          -- width = 0, -- full width
        },
      },
    },
    ---@class snacks.dashboard.Config
    dashboard = {
      width = 60,
      row = nil, -- dashboard position. nil for center
      col = nil, -- dashboard position. nil for center
      pane_gap = 4, -- empty columns between vertical panes
      autokeys = '1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', -- autokey sequence
      sections = {
        { text = get_header(), width = 2000, align = 'center', padding = 1 },
        { icon = '', title = 'Unstaged Changes', section = 'terminal', cmd = 'git diff --stat', height = 5, indent = 2, padding = 1 },
        { icon = ' ', title = 'Recent Files', section = 'recent_files', cwd = true, indent = 2, padding = 1 },
        { icon = '󰊢', key = 'g', desc = 'Neogit', action = ':Neogit' },
        { icon = '', key = 'G', desc = 'Git Status', action = ':lua Snacks.picker.git_status()' },
        { icon = '󱜙 ', key = 'a', desc = 'AI (Claude Code)', action = ':ClaudeCode' },
        { icon = ' ', key = 'f', desc = 'Go To File', action = ':GoToFile' },
        { icon = ' ', key = '/', desc = 'Find Text', action = ':Grep' },
        { icon = '󰩈', key = 'q', desc = 'Quit', action = ':qa' },
      },
    },
  },
  keys = {
    {
      '<leader>,',
      function()
        Snacks.picker.buffers()
      end,
      desc = 'Buffers',
    },
    {
      '<leader>/',
      function()
        ---@diagnostic disable-next-line: missing-fields
        Snacks.picker.grep {
          hidden = true,
        }
      end,
      desc = 'Grep',
    },
    {
      '<leader>:',
      function()
        Snacks.picker.command_history()
      end,
      desc = 'Command History',
    },
    -- find
    {
      '<leader>fb',
      function()
        Snacks.picker.buffers()
      end,
      desc = 'Buffers',
    },
    {
      '<leader>fc',
      function()
        ---@diagnostic disable-next-line: missing-fields
        Snacks.picker.files { cwd = print(vim.fn.stdpath 'config') }
      end,
      desc = 'Find Config File',
    },
    {
      '<leader>ff',
      function()
        Snacks.picker.files()
      end,
      desc = 'Find Files',
    },
    {
      '<leader>fg',
      function()
        Snacks.picker.git_files()
      end,
      desc = 'Find Git Files',
    },
    {
      '<leader>fr',
      function()
        Snacks.picker.recent()
      end,
      desc = 'Recent',
    },
    -- git
    {
      '<leader>gl',
      function()
        Snacks.picker.git_log()
      end,
      desc = '[g]it [l]og',
    },
    {
      '<leader>gs',
      function()
        Snacks.picker.git_status()
      end,
      desc = 'Git Status',
    },
    -- Grep
    {
      '<leader>sb',
      function()
        Snacks.picker.lines()
      end,
      desc = 'Buffer Lines',
    },
    {
      '<leader>sB',
      function()
        Snacks.picker.grep_buffers()
      end,
      desc = 'Grep Open Buffers',
    },
    {
      '<leader>sg',
      function()
        Snacks.picker.grep()
      end,
      desc = 'Grep',
    },
    {
      '<leader>sw',
      function()
        Snacks.picker.grep_word()
      end,
      desc = 'Visual selection or word',
      mode = { 'n', 'x' },
    },
    -- search
    {
      '<leader>s"',
      function()
        Snacks.picker.registers()
      end,
      desc = 'Registers',
    },
    {
      '<leader>sa',
      function()
        Snacks.picker.autocmds()
      end,
      desc = 'Autocmds',
    },
    {
      '<leader>sc',
      function()
        Snacks.picker.command_history()
      end,
      desc = 'Command History',
    },
    {
      '<leader>sC',
      function()
        Snacks.picker.commands()
      end,
      desc = 'Commands',
    },
    {
      '<leader>sd',
      function()
        Snacks.picker.diagnostics()
      end,
      desc = 'Diagnostics',
    },
    {
      '<leader>sh',
      function()
        Snacks.picker.help()
      end,
      desc = 'Help Pages',
    },
    {
      '<leader>sH',
      function()
        Snacks.picker.highlights()
      end,
      desc = 'Highlights',
    },
    {
      '<leader>sj',
      function()
        Snacks.picker.jumps()
      end,
      desc = 'Jumps',
    },
    {
      '<leader>sk',
      function()
        Snacks.picker.keymaps()
      end,
      desc = 'Keymaps',
    },
    {
      '<leader>sl',
      function()
        Snacks.picker.loclist()
      end,
      desc = 'Location List',
    },
    {
      '<leader>sM',
      function()
        Snacks.picker.man()
      end,
      desc = 'Man Pages',
    },
    {
      '<leader>sm',
      function()
        Snacks.picker.marks()
      end,
      desc = 'Marks',
    },
    {
      '<leader>sR',
      function()
        Snacks.picker.resume()
      end,
      desc = 'Resume',
    },
    {
      '<leader>sq',
      function()
        Snacks.picker.qflist()
      end,
      desc = 'Quickfix List',
    },
    {
      '<leader>uC',
      function()
        Snacks.picker.colorschemes()
      end,
      desc = 'Colorschemes',
    },
    {
      '<leader>qp',
      function()
        Snacks.picker.projects()
      end,
      desc = 'Projects',
    },
    -- LSP
    {
      'gd',
      function()
        Snacks.picker.lsp_definitions()
      end,
      desc = 'Goto Definition',
    },
    {
      'gr',
      function()
        Snacks.picker.lsp_references()
      end,
      nowait = true,
      desc = 'References',
    },
    {
      'gI',
      function()
        Snacks.picker.lsp_implementations()
      end,
      desc = 'Goto Implementation',
    },
    {
      'gy',
      function()
        Snacks.picker.lsp_type_definitions()
      end,
      desc = 'Goto T[y]pe Definition',
    },
    {
      '<leader>ss',
      function()
        Snacks.picker.lsp_symbols()
      end,
      desc = 'LSP Symbols',
    },
  },
}
