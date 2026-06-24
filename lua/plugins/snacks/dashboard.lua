-- The header (a rainbow figlet banner of the tmux session or cwd name) is
-- rendered lazily so it never blocks the dashboard paint. get_header() returns
-- the cached banner instantly, or a plain placeholder (cwd basename, no
-- subprocess) on the very first open. prime_header() shells out to tmux/figlet
-- asynchronously off the render path and swaps the banner in via
-- Snacks.dashboard.update(). Cached per session name, so reopens are instant
-- and only a changed name triggers a rebuild.
local header_cache = nil

---@return snacks.dashboard.Section
local function get_header()
  local text = header_cache and header_cache.text or vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
  return { width = 2000, align = 'center', padding = 1, text = text }
end

-- Cache issue/PR titles (keyed by "repo_root#branch", PR entries prefixed with
-- "pr:") so the slow gh calls only run once per branch. Backed by a single
-- on-disk JSON file that survives restarts; entries expire after
-- issue_title_ttl seconds. The in-memory table is the hot layer loaded lazily
-- from disk on first use.
--
-- The gh calls never run on the dashboard render path. The section functions
-- below only READ the cache (instant, non-blocking); prime_titles() does the
-- fetching asynchronously after the dashboard opens (see the autocmd near the
-- bottom of this file) and re-renders via Snacks.dashboard.update() once a
-- value actually changes. So a cold open shows nothing for these lines, then
-- they pop in when gh returns; a warm open renders the cached value
-- immediately, and a stale value is shown right away then quietly replaced in
-- the background.
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

-- Resolve repo root and current branch (cheap, local git). Returns nil when not
-- in a git repo so callers can bail out.
local function git_context()
  local root = Snacks.git.get_root()
  if not root then
    return
  end
  -- List form execs git directly, avoiding a (potentially slow) shell spawn.
  local branch = vim.fn.system { 'git', 'rev-parse', '--abbrev-ref', 'HEAD' }
  if vim.v.shell_error ~= 0 then
    return
  end
  return root, branch:gsub('%s+$', '')
end

---@return snacks.dashboard.Section?
local function get_issue_title()
  local root, branch = git_context()
  if not root or not branch then
    return
  end
  local number = branch:match '(%d+)'
  if not number then
    return
  end

  -- Read-only: prime_titles() owns fetching. A missing/false value renders nothing.
  local entry = load_issue_title_cache()[root .. '#' .. branch]
  if not entry or not entry.value then
    return
  end

  return {
    text = { { ('Issue #%s '):format(number), hl = 'Special' }, { entry.value, hl = 'Title' } },
    width = 2000,
    align = 'center',
    padding = 1,
  }
end

---@return snacks.dashboard.Section?
local function get_pr_title()
  local root, branch = git_context()
  if not root or not branch then
    return
  end

  -- Read-only: prime_titles() owns fetching. PR entries share the cache file
  -- under a "pr:" key prefix so they don't collide with issue entries.
  local entry = load_issue_title_cache()['pr:' .. root .. '#' .. branch]
  if not entry or not entry.value then
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

-- In-flight gh keys, so a re-render (or a rapid dashboard reopen) never spawns a
-- duplicate fetch for a key already being fetched.
local title_inflight = {}

-- Fetch one title asynchronously and refresh the cache. `validate(code, output)`
-- returns the string to cache, or false to remember a miss until the TTL lapses.
-- Only triggers a re-render when the cached value actually changed, avoiding
-- needless flicker.
local function refresh_title(key, cmd, validate)
  if title_inflight[key] then
    return
  end
  title_inflight[key] = true
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      title_inflight[key] = nil
      local output = (res.code == 0 and res.stdout or ''):gsub('%s+$', '')
      local value = validate(res.code, output)
      local cache = load_issue_title_cache()
      local prev = cache[key]
      cache[key] = { value = value, fetched_at = os.time() }
      save_issue_title_cache()
      if not prev or prev.value ~= value then
        Snacks.dashboard.update()
      end
    end)
  end)
end

-- Refetch issue/PR titles for the current branch when stale or missing. Runs
-- after the dashboard has already rendered, so the blocking gh network calls
-- never delay the initial paint. A cached entry with no `value` field is an
-- older on-disk schema and is treated as missing so it gets refilled.
local function prime_titles()
  local root, branch = git_context()
  if not root or not branch then
    return
  end
  local cache = load_issue_title_cache()
  local now = os.time()

  local function is_stale(key)
    local e = cache[key]
    return not e or e.value == nil or (now - e.fetched_at) > issue_title_ttl
  end

  local number = branch:match '(%d+)'
  if number then
    local key = root .. '#' .. branch
    if is_stale(key) then
      refresh_title(key, { 'gh', 'issue', 'view', number, '--json', 'title', '-q', '.title' }, function(code, output)
        return (code ~= 0 or output == '') and false or output
      end)
    end
  end

  local pr_key = 'pr:' .. root .. '#' .. branch
  if is_stale(pr_key) then
    -- gh resolves the PR from the current branch directly. Use jq interpolation
    -- ("number\ttitle"); '+' fails because gh's jq can't add a number to a string.
    refresh_title(pr_key, { 'gh', 'pr', 'view', '--json', 'number,title', '-q', '"\\(.number)\t\\(.title)"' }, function(code, output)
      -- Reject anything not shaped like "<digits><TAB>...": gh writes jq errors
      -- to stdout and still exits 0, which would otherwise poison the cache.
      return (code ~= 0 or not output:match '^%d+\t') and false or output
    end)
  end
end

-- Turn raw figlet output into per-character rainbow-highlighted chunks.
local function build_header_text(figlet)
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

local function set_header(name, text)
  header_cache = { name = name, text = text }
  Snacks.dashboard.update()
end

-- Build the figlet banner asynchronously (tmux → figlet, all off the render
-- path) and swap it in. Cached per session name, so a reopen for the same name
-- is a no-op and never re-renders.
local function prime_header()
  vim.system({ 'tmux', 'display-message', '-p', '#S' }, { text = true }, function(nres)
    vim.schedule(function()
      local name = (nres.code == 0 and nres.stdout or ''):gsub('%s+$', '')
      if name == '' then
        name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
      end
      if header_cache and header_cache.name == name then
        return
      end
      vim.system({ 'figlet', '-I', '2' }, { text = true }, function(dres)
        vim.schedule(function()
          local font_dir = dres.code == 0 and dres.stdout:gsub('%s+$', '') or ''
          local fonts = font_dir ~= '' and vim.fn.globpath(font_dir, '*.flf', false, true) or {}
          if #fonts == 0 then
            return set_header(name, name) -- plain-text fallback
          end
          math.randomseed(os.time())
          local font = fonts[math.random(#fonts)]
          vim.system({ 'figlet', '-w', '1000', '-f', font, name }, { text = true }, function(gres)
            vim.schedule(function()
              set_header(name, gres.code == 0 and build_header_text(gres.stdout) or name)
            end)
          end)
        end)
      end)
    end)
  end)
end

-- Prime the header and issue/PR titles once per dashboard open (fires after the
-- initial render), and never on the re-renders the primers themselves trigger.
vim.api.nvim_create_autocmd('User', {
  pattern = 'SnacksDashboardOpened',
  group = vim.api.nvim_create_augroup('dashboard_async_primer', { clear = true }),
  callback = function()
    prime_header()
    prime_titles()
  end,
})

-- Open Octo in a vertical split viewing the issue whose number is parsed from
-- the checked-out branch (e.g. "123-fix-thing" → issue #123).
local function view_branch_issue()
  local branch = vim.fn.system { 'git', 'rev-parse', '--abbrev-ref', 'HEAD' }
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
