--[[
██╗  ██╗███████╗██╗   ██╗███╗   ███╗ █████╗ ██████╗ ███████╗
██║ ██╔╝██╔════╝╚██╗ ██╔╝████╗ ████║██╔══██╗██╔══██╗██╔════╝
█████╔╝ █████╗   ╚████╔╝ ██╔████╔██║███████║██████╔╝███████╗
██╔═██╗ ██╔══╝    ╚██╔╝  ██║╚██╔╝██║██╔══██║██╔═══╝ ╚════██║
██║  ██╗███████╗   ██║   ██║ ╚═╝ ██║██║  ██║██║     ███████║
╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝
--]]

-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

vim.api.nvim_set_keymap('n', '<leader><space>', '<cmd>lua vim.lsp.buf.code_action()<CR>', { noremap = true, silent = true })

vim.keymap.set('n', '<leader>rN', function()
  return ':IncRename ' .. vim.fn.expand '<cword>'
end, { expr = true })

-- Exit insert mode with jk
vim.keymap.set('i', 'jk', '<Esc>', { desc = 'Exit insert mode' })

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- clipboard
vim.keymap.set('v', '<leader>y', '"+y', { desc = 'Yank to clipboard' })

-- Copy file path / selection reference for pasting into AI chats
local function copy_ref(opts)
  -- "%" is the current buffer's file name; ":." makes it relative to the cwd
  local path = vim.fn.expand '%:.'
  -- ref is what ends up in the clipboard; start with just the path
  local ref = path

  if opts.visual then
    -- '< and '> are only set after leaving visual mode, so read the live selection:
    -- "v" is the line where visual mode was started (the anchor)
    local start_line = vim.fn.line 'v'
    -- "." is the line the cursor is on now (the moving end of the selection)
    local end_line = vim.fn.line '.'
    -- if the selection was made upward, swap so start is always the smaller line
    if start_line > end_line then
      start_line, end_line = end_line, start_line
    end
    -- append the range, e.g. "lua/config/keymaps.lua:1:23"
    ref = path .. ':' .. start_line .. ':' .. end_line
  end

  -- ask for an optional free-text note on the command line (Enter to skip)
  local note = vim.fn.input 'Prompt (optional): '
  if note ~= '' then
    -- append the note after the ref, separated by a space
    ref = ref .. ' ' .. note
  end

  -- write ref into the "+" register, which is the system clipboard
  vim.fn.setreg('+', ref)
  -- show a confirmation message with what was copied
  vim.notify('Copied: ' .. ref)
end

-- normal mode: copy just the file path
vim.keymap.set('n', '<leader>Y', function()
  copy_ref {}
end, { desc = 'Copy file path' })

-- visual mode: copy the file path plus the selected line range
vim.keymap.set('v', '<leader>Y', function()
  copy_ref { visual = true }
end, { desc = 'Copy file path with line range' })

vim.keymap.set('n', '<Tab>', '<cmd>bn<cr>')
vim.keymap.set('n', '<S-Tab>', '<cmd>bp<cr>')

vim.keymap.set('n', '*', '*zz')

vim.keymap.set('n', 'n', 'nzz')
vim.keymap.set('n', 'N', 'Nzz')

vim.keymap.set('n', '<C-d>', '<C-d>zz')
vim.keymap.set('n', '<C-u>', '<C-u>zz')

vim.keymap.set('n', 'z0', '<CMD>setlocal foldlevel=0<CR>', { desc = 'Fold level 0' })
vim.keymap.set('n', 'z1', '<CMD>setlocal foldlevel=1<CR>', { desc = 'Fold level 1' })
vim.keymap.set('n', 'z2', '<CMD>setlocal foldlevel=2<CR>', { desc = 'Fold level 2' })
vim.keymap.set('n', 'z3', '<CMD>setlocal foldlevel=3<CR>', { desc = 'Fold level 3' })
vim.keymap.set('n', 'z4', '<CMD>setlocal foldlevel=4<CR>', { desc = 'Fold level 4' })
vim.keymap.set('n', 'z9', '<CMD>setlocal foldlevel=99<CR>', { desc = 'Fold level reset (99)' })

-- folds
vim.keymap.set('n', '<leader>z', '<cmd>normal! zMzv<cr>', { desc = 'Fold all others' })

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- TIP: Disable arrow keys in normal mode
-- vim.keymap.set('n', '<left>', '<cmd>echo "Use h to move!!"<CR>')
-- vim.keymap.set('n', '<right>', '<cmd>echo "Use l to move!!"<CR>')
-- vim.keymap.set('n', '<up>', '<cmd>echo "Use k to move!!"<CR>')
-- vim.keymap.set('n', '<down>', '<cmd>echo "Use j to move!!"<CR>')

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })
