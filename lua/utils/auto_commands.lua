--[[
 █████╗ ██╗   ██╗████████╗ ██████╗  ██████╗███╗   ███╗██████╗ ███████╗
██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗██╔════╝████╗ ████║██╔══██╗██╔════╝
███████║██║   ██║   ██║   ██║   ██║██║     ██╔████╔██║██║  ██║███████╗
██╔══██║██║   ██║   ██║   ██║   ██║██║     ██║╚██╔╝██║██║  ██║╚════██║
██║  ██║╚██████╔╝   ██║   ╚██████╔╝╚██████╗██║ ╚═╝ ██║██████╔╝███████║
╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝  ╚═════╝╚═╝     ╚═╝╚═════╝ ╚══════╝
See `:help lua-guide-autocommands`
--]]

vim.api.nvim_create_augroup('HelpSplitRight', { clear = true })
vim.api.nvim_create_autocmd('BufWinEnter', {
  group = 'HelpSplitRight',
  pattern = '*',
  callback = function()
    if vim.bo.buftype == 'help' then
      vim.cmd 'wincmd L'
    end
  end,
})

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = { '*tmux.conf' },
  command = "execute 'silent !tmux source <afile> --silent'",
})

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = { 'yazi.toml' },
  command = "execute 'silent !yazi --clear-cache'",
})

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = { 'config.fish' },
  command = "execute 'silent !source <afile> --silent'",
})

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = { 'aerospace.toml' },
  command = "execute 'silent !aerospace reload-config'",
})

vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufFilePre', 'BufRead' }, {
  pattern = { '*.mdx', '*.md' },
  callback = function()
    vim.cmd [[set filetype=markdown wrap linebreak nolist nospell]]
  end,
})

vim.api.nvim_create_autocmd({ 'BufRead' }, {
  pattern = { 'gitcommit' },
  callback = function()
    vim.cmd [[set wrap linebreak]]
  end,
})

vim.api.nvim_create_autocmd({ 'BufRead' }, {
  pattern = { '*.conf' },
  callback = function()
    vim.cmd [[set filetype=sh]]
  end,
})

vim.api.nvim_create_autocmd({ 'BufRead' }, {
  pattern = { '*.glsl' },
  callback = function()
    vim.cmd [[set shiftwidth=4]]
    vim.cmd [[set tabstop=4]]
  end,
})

vim.api.nvim_create_autocmd({ 'BufRead' }, {
  pattern = { '*.gltf' },
  callback = function()
    vim.cmd [[set filetype=json]]
  end,
})

vim.api.nvim_create_autocmd({ 'BufRead' }, {
  -- https://ghostty.org/docs/config/reference
  pattern = { 'config' },
  callback = function()
    vim.cmd [[set filetype=toml]]
    vim.cmd [[LspStop]]
  end,
})

vim.api.nvim_create_autocmd('BufDelete', {
  desc = 'Open dashboard when last buffer is closed',
  group = vim.api.nvim_create_augroup('dashboard-on-empty', { clear = true }),
  callback = function()
    vim.schedule(function()
      local bufs = vim.tbl_filter(function(b)
        if not vim.api.nvim_buf_is_valid(b) then
          return false
        end
        local name = vim.api.nvim_buf_get_name(b)
        if name:match '^oil://' then
          return true
        end
        return vim.bo[b].buflisted and vim.bo[b].buftype == '' and name ~= ''
      end, vim.api.nvim_list_bufs())
      if #bufs == 0 then
        Snacks.dashboard.open()
      end
    end)
  end,
})

-- Detect external file changes (e.g. Claude Code edits)
vim.api.nvim_create_autocmd({ 'FocusGained', 'CursorHold' }, {
  group = vim.api.nvim_create_augroup('claude-checktime', { clear = true }),
  command = 'silent! checktime',
})

-- Save buffer content before reload for diff comparison
vim.api.nvim_create_autocmd('FileChangedShell', {
  group = vim.api.nvim_create_augroup('claude-focus-changed-line', { clear = true }),
  callback = function(args)
    local bufnr = args.buf
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.b[bufnr]._pre_reload_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end
  end,
})

-- Jump to first changed line after external reload
vim.api.nvim_create_autocmd('FileChangedShellPost', {
  group = 'claude-focus-changed-line',
  callback = function(args)
    local bufnr = args.buf
    local old_lines = vim.b[bufnr]._pre_reload_lines
    vim.b[bufnr]._pre_reload_lines = nil

    if not old_lines then
      return
    end

    local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local first_changed = nil
    local max_len = math.max(#old_lines, #new_lines)
    for i = 1, max_len do
      if old_lines[i] ~= new_lines[i] then
        first_changed = i
        break
      end
    end

    if first_changed then
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
          vim.api.nvim_win_set_cursor(win, { first_changed, 0 })
          vim.api.nvim_win_call(win, function()
            vim.cmd 'normal! zz'
          end)
          break
        end
      end
    end
  end,
})

-- vim.api.nvim_create_autocmd('BufWritePost', {
--   pattern = { 'sketchybarrc' },
--   command = '!brew services restart sketchybar',
-- })
