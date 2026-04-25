local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO)
end

local function current_file_paths()
  local absolute = vim.fn.expand '%:p'
  if absolute == '' then
    notify('No file open', vim.log.levels.WARN)
    return nil
  end

  return {
    absolute = absolute,
    relative = vim.fn.expand '%:.',
    ft = vim.bo.filetype,
  }
end

local function current_buffer_message(prompt)
  local file = current_file_paths()
  if not file then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, '\n')

  if prompt and prompt ~= '' then
    return string.format('%s\n\nFile: %s\n```%s\n%s\n```', prompt, file.relative, file.ft, content)
  end

  return string.format('Look at this file %s:\n\n```%s\n%s\n```', file.relative, file.ft, content)
end

local function current_file_message(prompt)
  local file = current_file_paths()
  if not file then
    return nil
  end

  if prompt and prompt ~= '' then
    return string.format('File: %s\n\n%s', file.absolute, prompt)
  end

  return string.format('Look at this file: %s', file.absolute)
end

local function current_selection_data()
  local start_pos = vim.fn.getpos "'<"
  local end_pos = vim.fn.getpos "'>"
  local lines = vim.fn.getregion(start_pos, end_pos, { type = vim.fn.visualmode() })
  local selection = table.concat(lines, '\n')

  if selection == '' then
    notify('Empty selection', vim.log.levels.WARN)
    return nil
  end

  return {
    file = vim.fn.expand '%:.',
    ft = vim.bo.filetype,
    selection = selection,
    start_line = start_pos[2],
    end_line = end_pos[2],
  }
end

local function selection_message(prompt)
  local data = current_selection_data()
  if not data then
    return nil
  end

  local header = string.format('%s lines %d-%d', data.file, data.start_line, data.end_line)

  if prompt and prompt ~= '' then
    return string.format('%s\n\nFrom %s:\n```%s\n%s\n```', prompt, header, data.ft, data.selection)
  end

  return string.format('Look at this code from %s:\n\n```%s\n%s\n```', header, data.ft, data.selection)
end

local function send_to_pi(message)
  if not message then
    return
  end

  require('pi-nvim').prompt(message)
end

local function focus_tmux_last_pane()
  if not vim.env.TMUX then
    notify('Not running inside tmux', vim.log.levels.WARN)
    return
  end

  vim.fn.system { 'tmux', 'last-pane' }
  if vim.v.shell_error ~= 0 then
    notify('Failed to focus the last tmux pane', vim.log.levels.ERROR)
  end
end

local function send_file_now()
  send_to_pi(current_file_message())
end

local function send_buffer_now()
  send_to_pi(current_buffer_message())
end

local function review_current_file()
  send_to_pi(current_file_message 'Review this file and suggest improvements. Focus on correctness, maintainability, repo style, and Neovim/Lua best practices.')
end

local function in_visual_mode()
  local mode = vim.fn.mode()
  return mode == 'v' or mode == 'V' or mode == '\22'
end

local function explain_with_pi()
  if in_visual_mode() then
    send_to_pi(selection_message 'Explain this code. Describe what it does, any risks, and anything non-obvious I should know.')
  else
    send_to_pi(current_file_message 'Explain this file. Describe what it does, any risks, and anything non-obvious I should know.')
  end
end

local function refactor_with_pi()
  if in_visual_mode() then
    send_to_pi(selection_message 'Refactor this code to be clearer and more idiomatic while preserving behavior. Explain any tradeoffs.')
  else
    send_to_pi(current_file_message 'Refactor this file to be clearer and more idiomatic while preserving behavior. Explain any tradeoffs.')
  end
end

local function handoff_to_pi()
  if in_visual_mode() then
    send_to_pi(selection_message())
  else
    send_to_pi(current_file_message())
  end
  focus_tmux_last_pane()
end

return {
  'carderne/pi-nvim',
  -- Requires the pi-side extension too:
  --   pi install npm:pi-nvim
  -- Then restart pi or run /reload.
  cmd = {
    'Pi',
    'PiSend',
    'PiSendFile',
    'PiSendSelection',
    'PiSendBuffer',
    'PiPing',
    'PiSessions',
    'PiSendFileNow',
    'PiSendBufferNow',
    'PiReview',
    'PiExplain',
    'PiRefactor',
    'PiFocus',
    'PiHandOff',
  },
  keys = {
    { '<leader>p', '<cmd>Pi<cr>', mode = { 'n', 'v' }, desc = 'Open pi dialog' },
    { '<leader>pp', '<cmd>PiSend<cr>', mode = 'n', desc = 'Send prompt to pi' },
    { '<leader>pp', '<cmd>PiSendSelection<cr>', mode = 'v', desc = 'Send selection to pi' },
    { '<leader>pf', '<cmd>PiSendFile<cr>', desc = 'Send file to pi' },
    { '<leader>pF', send_file_now, desc = 'Send file to pi now' },
    { '<leader>pb', '<cmd>PiSendBuffer<cr>', desc = 'Send buffer to pi' },
    { '<leader>pB', send_buffer_now, desc = 'Send buffer to pi now' },
    { '<leader>pr', review_current_file, mode = 'n', desc = 'Review current file with pi' },
    { '<leader>pe', explain_with_pi, mode = { 'n', 'v' }, desc = 'Explain with pi' },
    { '<leader>px', refactor_with_pi, mode = { 'n', 'v' }, desc = 'Refactor with pi' },
    { '<leader>pt', handoff_to_pi, mode = { 'n', 'v' }, desc = 'Hand off to pi + focus tmux pane' },
    { '<leader>pT', focus_tmux_last_pane, desc = 'Focus last tmux pane' },
    { '<leader>pi', '<cmd>PiPing<cr>', desc = 'Ping pi' },
    { '<leader>pj', '<cmd>PiSessions<cr>', desc = 'Switch pi session' },
  },
  config = function()
    require('pi-nvim').setup()

    vim.api.nvim_create_user_command('PiSendFileNow', send_file_now, { desc = 'Send the current file to pi without prompting' })
    vim.api.nvim_create_user_command('PiSendBufferNow', send_buffer_now, { desc = 'Send the current buffer to pi without prompting' })
    vim.api.nvim_create_user_command('PiReview', review_current_file, { desc = 'Ask pi to review the current file' })
    vim.api.nvim_create_user_command('PiExplain', explain_with_pi, { range = true, desc = 'Ask pi to explain the current selection or file' })
    vim.api.nvim_create_user_command('PiRefactor', refactor_with_pi, { range = true, desc = 'Ask pi to refactor the current selection or file' })
    vim.api.nvim_create_user_command('PiFocus', focus_tmux_last_pane, { desc = 'Focus the last tmux pane' })
    vim.api.nvim_create_user_command('PiHandOff', handoff_to_pi, { range = true, desc = 'Send context to pi and focus tmux' })
  end,
}
