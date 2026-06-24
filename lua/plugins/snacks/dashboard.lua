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

-- Cache issue titles per branch so the (slow, blocking) gh call only runs
-- once per branch per Neovim session.
local issue_title_cache = {}

---@return snacks.dashboard.Section?
local function get_issue_title()
  if not Snacks.git.get_root() then
    return
  end

  local branch = vim.fn.system 'git rev-parse --abbrev-ref HEAD'
  if vim.v.shell_error ~= 0 then
    return
  end
  branch = branch:gsub('%s+$', '')

  local number = branch:match '(%d+)'
  if not number then
    return
  end

  local title = issue_title_cache[branch]
  if title == nil then
    title = vim.fn.system { 'gh', 'issue', 'view', number, '--json', 'title', '-q', '.title' }
    if vim.v.shell_error ~= 0 or title:match '^%s*$' then
      issue_title_cache[branch] = false -- remember the miss, don't refetch
      return
    end
    title = title:gsub('%s+$', '')
    issue_title_cache[branch] = title
  end
  if not title then
    return
  end

  return {
    text = { { ('#%s '):format(number), hl = 'Special' }, { title, hl = 'Title' } },
    width = 2000,
    align = 'center',
    padding = 1,
  }
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
    get_issue_title,
    -- get_unstaged_changes,
    { icon = '⏳', title = 'Recent Files', section = 'recent_files', cwd = true, indent = 2, padding = 1 },
    { icon = '📑', key = 'f', desc = 'Files', action = ':GoToFile' },
    { icon = '🤖', key = 'c', desc = 'Claude Code', action = ':ClaudeCode' },
    { icon = '🤖', key = 'p', desc = 'Pi (tmux split)', action = ':silent !tmux split-window -h pi' },
    { icon = '📝', key = 'P', desc = 'Claude Code (Plan)', action = ':ClaudeCode --permission-mode plan' },
    { icon = '⏩︎', key = 'r', desc = 'Claude Code (Resume)', action = ':ClaudeCode --resume' },
    { icon = '⏭️', key = 'C', desc = 'Claude Code (Continue)', action = ':ClaudeCode --continue' },
    { icon = '🌳', key = 'g', desc = 'Neogit', action = ':Neogit' },
    { icon = '🔎', key = '/', desc = 'Find Text', action = ':Grep' },
    { icon = '🌳', key = 'G', desc = 'Git Status', action = ':lua Snacks.picker.git_status()' },
    { icon = '🔄', key = 'R', desc = 'Reload Dashboard', action = ':lua Snacks.dashboard.open()' },
    { icon = '👋', key = 'q', desc = 'Quit', action = ':qa' },
  },
}
