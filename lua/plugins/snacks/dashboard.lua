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

-- Cache issue titles (keyed by "repo_root#branch") so the slow, blocking gh
-- call only runs once per branch. Backed by a single on-disk JSON file that
-- survives restarts; entries expire after issue_title_ttl seconds. The
-- in-memory table is the hot layer loaded lazily from disk on first use.
local issue_title_cache = nil
local issue_title_ttl = 24 * 60 * 60 -- 24h
local issue_title_cache_file = vim.fs.joinpath(vim.fn.stdpath 'cache', 'dashboard_issue_titles.json')

local function load_issue_title_cache()
  if issue_title_cache then
    return issue_title_cache
  end
  issue_title_cache = {}
  local ok, lines = pcall(vim.fn.readfile, issue_title_cache_file)
  if ok and #lines > 0 then
    local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
    if decoded_ok and type(decoded) == 'table' then
      issue_title_cache = decoded
    end
  end
  return issue_title_cache
end

local function save_issue_title_cache()
  pcall(vim.fn.writefile, { vim.json.encode(issue_title_cache) }, issue_title_cache_file)
end

---@return snacks.dashboard.Section?
local function get_issue_title()
  local root = Snacks.git.get_root()
  if not root then
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

  local cache = load_issue_title_cache()
  local key = root .. '#' .. branch
  local entry = cache[key]

  if not entry or (os.time() - entry.fetched_at) > issue_title_ttl then
    local output = vim.fn.system { 'gh', 'issue', 'view', number, '--json', 'title', '-q', '.title' }
    -- false remembers a miss so we don't refetch until the TTL lapses
    local title = (vim.v.shell_error ~= 0 or output:match '^%s*$') and false or output:gsub('%s+$', '')
    entry = { title = title, fetched_at = os.time() }
    cache[key] = entry
    save_issue_title_cache()
  end

  if not entry.title then
    return
  end

  return {
    text = { { ('Issue #%s '):format(number), hl = 'Special' }, { entry.title, hl = 'Title' } },
    width = 2000,
    align = 'center',
    padding = 1,
  }
end

---@return snacks.dashboard.Section?
local function get_pr_title()
  local root = Snacks.git.get_root()
  if not root then
    return
  end

  local branch = vim.fn.system 'git rev-parse --abbrev-ref HEAD'
  if vim.v.shell_error ~= 0 then
    return
  end
  branch = branch:gsub('%s+$', '')

  -- Reuse the issue title cache, namespaced with a "pr:" key prefix so issue
  -- and PR entries share the same on-disk file without colliding.
  local cache = load_issue_title_cache()
  local key = 'pr:' .. root .. '#' .. branch
  local entry = cache[key]

  if not entry or (os.time() - entry.fetched_at) > issue_title_ttl then
    -- gh resolves the PR from the current branch directly, so no parsing of the
    -- branch name is needed. false remembers a miss until the TTL lapses.
    local output = vim.fn.system { 'gh', 'pr', 'view', '--json', 'number,title', '-q', '"\\(.number)\t\\(.title)"' }
    local value = (vim.v.shell_error ~= 0 or output:match '^%s*$') and false or output:gsub('%s+$', '')
    entry = { value = value, fetched_at = os.time() }
    cache[key] = entry
    save_issue_title_cache()
  end

  if not entry.value then
    return
  end

  local number, title = entry.value:match '^(%d+)\t(.*)$'
  if not number then
    return
  end

  return {
    text = { { ('PR #%s '):format(number), hl = 'Special' }, { title, hl = 'Title' } },
    width = 2000,
    align = 'center',
    padding = 1,
  }
end

-- Open Octo in a vertical split viewing the issue whose number is parsed from
-- the checked-out branch (e.g. "123-fix-thing" → issue #123).
local function view_branch_issue()
  local branch = vim.fn.system 'git rev-parse --abbrev-ref HEAD'
  if vim.v.shell_error ~= 0 then
    return vim.notify('Not in a git repository', vim.log.levels.WARN)
  end
  branch = branch:gsub('%s+$', '')

  local number = branch:match '(%d+)'
  if not number then
    return vim.notify(('No issue number found in branch "%s"'):format(branch), vim.log.levels.WARN)
  end

  vim.cmd 'vsplit'
  vim.cmd('Octo issue edit ' .. number)
end

-- Open Octo in a vertical split viewing the pull request associated with the
-- checked-out branch. gh resolves the PR from the current branch directly, so
-- no parsing is needed; exits with a notice when the branch has no PR.
local function view_branch_pr()
  if not Snacks.git.get_root() then
    return vim.notify('Not in a git repository', vim.log.levels.WARN)
  end

  local number = vim.fn.system { 'gh', 'pr', 'view', '--json', 'number', '-q', '.number' }
  if vim.v.shell_error ~= 0 or number:match '^%s*$' then
    return vim.notify('No pull request found for the current branch', vim.log.levels.WARN)
  end
  number = number:gsub('%s+$', '')

  vim.cmd 'vsplit'
  vim.cmd('Octo pr edit ' .. number)
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
  formats = {
    -- Show recent files relative to Neovim's cwd (`:.`) instead of home (`:~`).
    file = function(item, ctx)
      local fname = vim.fn.fnamemodify(item.file, ':.')
      fname = ctx.width and #fname > ctx.width and vim.fn.pathshorten(fname) or fname
      if #fname > ctx.width then
        local dir = vim.fn.fnamemodify(fname, ':h')
        local file = vim.fn.fnamemodify(fname, ':t')
        if dir and file then
          file = file:sub(-(ctx.width - #dir - 2))
          fname = dir .. '/…' .. file
        end
      end
      local dir, file = fname:match '^(.*)/(.+)$'
      return dir and { { dir .. '/', hl = 'dir' }, { file, hl = 'file' } } or { { fname, hl = 'file' } }
    end,
  },
  sections = {
    get_header,
    get_issue_title,
    get_pr_title,
    -- get_unstaged_changes,
    { icon = '⏳', title = 'Recent Files', section = 'recent_files', cwd = true, indent = 2, padding = 1 },
    { icon = '📑', key = 'f', desc = 'Files', action = ':GoToFile' },
    { icon = '🐙', key = 'i', desc = 'View Issue (branch)', action = view_branch_issue },
    { icon = '🔀', key = 'p', desc = 'View PR (branch)', action = view_branch_pr },
    { icon = '🤖', key = 'c', desc = 'Claude Code', action = ':ClaudeCode' },
    { icon = '🤖', key = 'a', desc = 'AI (pi)', action = ':silent !tmux split-window -h pi' },
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
