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

-- Render a status as an inverted "chip": the word in a filled pill with
-- half-circle end caps (Nerd Font U+E0B6 / U+E0B4). The label is auto-contrasted
-- onto the fill color and the caps paint the fill on a transparent cell so the
-- rounded ends blend with the terminal background. Each chip is drawn in a named
-- "tone"; tone colors come from the active theme's Diagnostic*/Special/Comment
-- groups and are refreshed on ColorScheme so they follow dark/light switches.
local CHIP_LEFT = '\238\130\182' -- U+E0B6 left half circle
local CHIP_RIGHT = '\238\130\180' -- U+E0B4 right half circle
local chip_tone_src = {
  gray = 'Comment',
  green = 'DiagnosticOk',
  red = 'DiagnosticError',
  yellow = 'DiagnosticWarn',
  blue = 'DiagnosticInfo',
  accent = 'Special',
}

-- Pick black or white for the pill label based on the fill's luminance (YIQ),
-- so the chip stays readable on both light and dark tone colors. Can't invert
-- to Normal.bg here: with transparent_background it's nil.
local function readable_fg(rgb)
  local r, g, b = math.floor(rgb / 65536) % 256, math.floor(rgb / 256) % 256, rgb % 256
  return (r * 299 + g * 587 + b * 114) / 1000 > 140 and 0x000000 or 0xffffff
end

local function setup_chip_hls()
  for tone, src in pairs(chip_tone_src) do
    local color = vim.api.nvim_get_hl(0, { name = src, link = false }).fg
    if color then
      vim.api.nvim_set_hl(0, 'DashboardChip_' .. tone, { fg = readable_fg(color), bg = color, bold = true })
      vim.api.nvim_set_hl(0, 'DashboardChip_' .. tone .. '_cap', { fg = color })
    end
  end
end

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('dashboard_chip_hl', { clear = true }),
  callback = setup_chip_hls,
})
pcall(setup_chip_hls)

-- Build the chip chunks for a label in the given tone (falling back to accent).
local function chip(label, tone)
  tone = chip_tone_src[tone] and tone or 'accent'
  return {
    { CHIP_LEFT, hl = 'DashboardChip_' .. tone .. '_cap' },
    { (' %s '):format(label), hl = 'DashboardChip_' .. tone },
    { CHIP_RIGHT, hl = 'DashboardChip_' .. tone .. '_cap' },
  }
end

-- Issue/PR state → chip word + tone. Draft PRs report state OPEN but are
-- collapsed to DRAFT upstream.
local state_chip_spec = {
  OPEN = { 'OPEN', 'green' },
  CLOSED = { 'CLOSED', 'red' },
  MERGED = { 'MERGED', 'accent' },
  DRAFT = { 'DRAFT', 'gray' },
}
local function state_chip(state)
  local spec = state_chip_spec[state]
  if spec then
    return chip(spec[1], spec[2])
  end
  return chip(state or '?', 'gray')
end

-- Map a GitHub Projects status name (free-form, e.g. "In Progress") to a tone.
local function project_tone(status)
  local s = status:lower()
  if s:find 'progress' then
    return 'yellow'
  elseif s:find 'review' then
    return 'blue'
  elseif s:find 'done' or s:find 'complete' then
    return 'green'
  elseif s:find 'todo' or s:find 'backlog' or s:find 'triage' then
    return 'gray'
  end
  return 'accent'
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
  -- "<STATE>\t<project status>\t<title>"; the project status may be empty.
  local state, project, title = entry.value:match '^(%u+)\t([^\t]*)\t(.*)$'
  if not state then
    return
  end

  -- Line 1: chips + "Issue #N". Line 2 (after the newline chunk): the title.
  local text = state_chip(state)
  if project ~= '' then
    vim.list_extend(text, chip(project, project_tone(project)))
  end
  table.insert(text, { (' Issue #%s'):format(number), hl = 'Special' })
  table.insert(text, { '\n' })
  table.insert(text, { title, hl = 'Title' })
  return { text = text, width = 2000, align = 'center', padding = 1 }
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

  local number, state, title = entry.value:match '^(%d+)\t(%u+)\t(.*)$'
  if not number then
    return
  end

  -- Line 1: chip + "PR #N". Line 2 (after the newline chunk): the title.
  local text = state_chip(state)
  table.insert(text, { (' PR #%s'):format(number), hl = 'Special' })
  table.insert(text, { '\n' })
  table.insert(text, { title, hl = 'Title' })
  return { text = text, width = 2000, align = 'center', padding = 1 }
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

  -- Refetch when missing, expired, an older schema (no value field), or a
  -- cached string that no longer matches the expected shape (so adding the
  -- state field auto-migrates stale entries instead of waiting out the TTL). A
  -- `false` miss is kept until the TTL lapses.
  local function needs_fetch(key, shape)
    local e = cache[key]
    if not e or e.value == nil then
      return true
    end
    if type(e.value) == 'string' and not e.value:match(shape) then
      return true
    end
    return (now - e.fetched_at) > issue_title_ttl
  end

  local number = branch:match '(%d+)'
  if number then
    local key = root .. '#' .. branch
    if needs_fetch(key, '^%u+\t[^\t]*\t') then
      -- Also pull the issue's GitHub Projects status (first project item; empty
      -- when the issue is in no project). // "" keeps jq null-safe.
      refresh_title(
        key,
        { 'gh', 'issue', 'view', number, '--json', 'state,title,projectItems', '-q', '"\\(.state)\t\\(.projectItems[0].status.name // "")\t\\(.title)"' },
        function(code, output)
          -- Expect "<STATE><TAB><project><TAB>title"; reject anything else as a miss.
          return (code ~= 0 or not output:match '^%u+\t[^\t]*\t') and false or output
        end
      )
    end
  end

  local pr_key = 'pr:' .. root .. '#' .. branch
  if needs_fetch(pr_key, '^%d+\t%u+\t') then
    -- gh resolves the PR from the current branch directly. Use jq interpolation
    -- ("number\tstate\ttitle"); '+' fails because gh's jq can't add a number to a
    -- string. A draft PR reports state OPEN, so collapse isDraft into "DRAFT".
    refresh_title(
      pr_key,
      { 'gh', 'pr', 'view', '--json', 'number,state,title,isDraft', '-q', '"\\(.number)\t\\(if .isDraft then "DRAFT" else .state end)\t\\(.title)"' },
      function(code, output)
        -- Reject anything not shaped like "<digits><TAB><STATE><TAB>...": gh writes
        -- jq errors to stdout and still exits 0, which would otherwise poison the cache.
        return (code ~= 0 or not output:match '^%d+\t%u+\t') and false or output
      end
    )
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
