---@return snacks.dashboard.Section
local function get_header()
  local name = vim.fn.system 'tmux display-message -p "#S"'
  if vim.v.shell_error ~= 0 or name:match '^%s*$' then
    name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
  else
    name = name:gsub('%s+$', '')
  end

  local section = { width = 2000, align = 'center', padding = 1 }

  local font_dir = vim.fn.system('figlet -I 2'):gsub('%s+$', '')
  if vim.v.shell_error ~= 0 then
    section.text = name
    return section
  end
  local fonts = vim.fn.globpath(font_dir, '*.flf', false, true)
  if #fonts == 0 then
    section.text = name
    return section
  end
  math.randomseed(os.time())
  local font = fonts[math.random(#fonts)]

  local figlet = vim.fn.system { 'figlet', '-w', '1000', '-f', font, name }
  if vim.v.shell_error ~= 0 then
    section.text = name
    return section
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
  section.text = result
  return section
end

---@return snacks.dashboard.Section?
local function get_unstaged_changes()
  if not Snacks.git.get_root() then
    return
  end
  local result = vim.fn.system 'git status --porcelain'
  if vim.v.shell_error ~= 0 or result:match '^%s*$' then
    return
  end
  return {
    icon = '👀',
    title = 'Unstaged Changes',
    section = 'terminal',
    cmd = 'git diff --stat',
    height = 5,
    indent = 2,
    padding = 1,
    ttl = 0,
  }
end

---@type snacks.dashboard.Config
return {
  width = 60,
  row = nil, -- dashboard position. nil for center
  col = nil, -- dashboard position. nil for center
  pane_gap = 4, -- empty columns between vertical panes
  autokeys = 'jklhfdsa123456789', -- autokey sequence
  formats = {},
  sections = {
    get_header,
    -- get_unstaged_changes,
    { icon = '⏳', title = 'Recent Files', section = 'recent_files', cwd = true, indent = 2, padding = 1 },
    { icon = '📝', key = 'f', desc = 'Files', action = ':GoToFile' },
    { icon = '🤖 ', key = 'c', desc = 'Claude Code', action = ':ClaudeCode' },
    { icon = '🌳', key = 'g', desc = 'Neogit', action = ':Neogit' },
    { icon = '🔎', key = '/', desc = 'Find Text', action = ':Grep' },
    { icon = '🌳', key = 'G', desc = 'Git Status', action = ':lua Snacks.picker.git_status()' },
    { icon = '🔄', key = 'r', desc = 'Reload Dashboard', action = ':lua Snacks.dashboard.open()' },
    { icon = '👋', key = 'q', desc = 'Quit', action = ':qa' },
  },
}
