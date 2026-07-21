-- The header (a rainbow figlet banner of the tmux session or cwd name) is
-- rendered lazily so it never blocks the dashboard paint. get_header() returns
-- the cached banner instantly, or a plain placeholder (cwd basename, no
-- subprocess) on the very first open. prime_header() shells out to tmux/figlet
-- asynchronously off the render path and swaps the banner in via
-- Snacks.dashboard.update(). Cached per session name, so reopens are instant
-- and only a changed name triggers a rebuild.
local header_cache = nil

-- Figlet fonts bundled with this config (e.g. "ANSI Shadow"), added to the
-- random banner pool alongside figlet's own installed fonts. Resolved relative
-- to this file (lua/plugins/snacks/dashboard.lua → repo root → /fonts) so it
-- works wherever the config is checked out.
local bundled_font_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h:h') .. '/fonts'

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
-- Labels are normalized to first-letter-capitalized (e.g. OPEN -> Open) unless
-- `raw` is set (e.g. to preserve the "PR" abbreviation).
local function chip(label, tone, raw)
  tone = chip_tone_src[tone] and tone or 'accent'
  if not raw then
    label = label:sub(1, 1):upper() .. label:sub(2):lower()
  end
  return {
    { CHIP_LEFT, hl = 'DashboardChip_' .. tone .. '_cap' },
    { (' %s '):format(label), hl = 'DashboardChip_' .. tone },
    { CHIP_RIGHT, hl = 'DashboardChip_' .. tone .. '_cap' },
  }
end

-- Concatenate chip chunk-lists into one line of text chunks, with a space
-- between each chip.
local function chip_row(chips)
  local text = {}
  for i, c in ipairs(chips) do
    if i > 1 then
      table.insert(text, { ' ' })
    end
    vim.list_extend(text, c)
  end
  return text
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

  -- Line 1: the title (default fg). Line 2: chips ("Issue #N" first, state, optional project).
  local chips = { chip(('Issue #%s'):format(number), 'accent') }
  table.insert(chips, state_chip(state))
  if project ~= '' then
    table.insert(chips, chip(project, project_tone(project)))
  end
  local text = { { title, hl = 'Normal' }, { '\n' } }
  vim.list_extend(text, chip_row(chips))
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

  -- Line 1: the title (default fg). Line 2: chips ("PR #N" first, state).
  local text = { { title, hl = 'Normal' }, { '\n' } }
  vim.list_extend(text, chip_row { chip(('PR #%s'):format(number), 'accent', true), state_chip(state) })
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

-- Recent Claude Code conversations for the current project, newest first. Each
-- entry is { id = <session uuid>, title = <aiTitle> }. Populated asynchronously
-- by prime_recent_convos(); the section function only reads it.
local recent_convos = {}

-- Gather the 5 most recent conversations for ONE project directory ($1). Claude
-- Code stores one .jsonl per session under ~/.claude/projects/<encoded-cwd>/
-- (cwd with '/' and '.' replaced by '-'), so scoping to the current project is
-- just globbing that single folder; file mtime is recency. Labels come from the
-- shared claude_label cascade (aiTitle → /command — args → last prompt → first
-- assistant sentence) so command/skill-started sessions read meaningfully
-- instead of "Untitled" here, exactly as they do in the picker. Emits
-- "<id>\t<title>" lines; runs off the render path.
local recent_convos_cmd = require 'plugins.snacks.claude_label'
  .. [[
dir=$1
[ -d "$dir" ] || exit 0
n=0
for f in $(ls -t "$dir"/*.jsonl 2>/dev/null | head -5); do
  [ "$n" -ge 5 ] && break
  title=$(claude_label "$f")
  printf '%s\t%s\n' "$(basename "$f" .jsonl)" "$title"
  n=$((n+1))
done
]]

-- Don't respawn the gather while one is already in flight (rapid reopens).
local recent_convos_inflight = false

-- Map the current working directory to its Claude Code project folder. Claude
-- Code encodes the cwd by replacing every non-alphanumeric character with '-'
-- (so '/', '.', '_', etc. all collapse to dashes) — matching that exactly is
-- what lets paths like "joshmedeski_com" resolve to "joshmedeski-com" on disk.
local function claude_project_dir()
  local encoded = vim.fn.getcwd():gsub('[^%w]', '-')
  return vim.fs.joinpath(vim.fn.expand '~/.claude/projects', encoded)
end

-- Refresh the recent-conversations list off the main thread, then re-render.
-- Like prime_titles, this runs after the dashboard has painted so the jq/file
-- scanning never blocks the initial open.
local function prime_recent_convos()
  if recent_convos_inflight then
    return
  end
  recent_convos_inflight = true
  vim.system({ 'bash', '-c', recent_convos_cmd, 'recent_convos', claude_project_dir() }, { text = true }, function(res)
    vim.schedule(function()
      recent_convos_inflight = false
      if res.code ~= 0 then
        return
      end
      local list = {}
      for line in vim.gsplit(res.stdout or '', '\n', { plain = true }) do
        local id, title = line:match '^([^\t]+)\t(.*)$'
        if id then
          list[#list + 1] = { id = id, title = title }
        end
      end
      recent_convos = list
      Snacks.dashboard.update()
    end)
  end)
end

---@return snacks.dashboard.Section?
local function get_recent_conversations()
  if #recent_convos == 0 then
    return
  end
  local cwd = vim.fn.getcwd()
  -- Title + child rows; snacks prepends the title header only when rows exist.
  local section = { icon = '💬', title = 'Recent Conversations', indent = 2, padding = 1 }
  for _, c in ipairs(recent_convos) do
    -- All rows are this project's conversations, so the title alone is the
    -- label (untitled sessions fall back to a short id).
    local label = c.title ~= '' and c.title or ('Untitled (' .. c.id:sub(1, 8) .. ')')
    -- Trim by display columns (not bytes) so the title never overflows the
    -- dashboard box or gets sliced mid-character.
    if vim.fn.strdisplaywidth(label) > 44 then
      label = vim.fn.strcharpart(label, 0, 43) .. '…'
    end
    -- Resume in a horizontal tmux split in this project's directory.
    local action = (':silent !tmux split-window -h -c %s claude --resume %s'):format(vim.fn.shellescape(cwd), c.id)
    section[#section + 1] = { icon = '💬', desc = label, action = action, autokey = true }
  end
  return section
end

-- Turn raw figlet output into per-character rainbow-highlighted chunks. Some
-- fonts (e.g. ANSI Shadow) use multi-byte UTF-8 box-drawing characters, so we
-- must iterate by character, not by byte (Lua's `.` pattern matches bytes and
-- would split a single character into invalid fragments, corrupting the
-- width calculation snacks uses to center the header).
local function build_header_text(figlet)
  local rainbow = { 'Rainbow1', 'Rainbow2', 'Rainbow3', 'Rainbow4', 'Rainbow5', 'Rainbow6' }
  local result = {}
  local color_idx = 1
  local nchars = vim.fn.strchars(figlet)
  for i = 0, nchars - 1 do
    local char = vim.fn.strcharpart(figlet, i, 1)
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
      -- Trim to the part before an em dash (e.g. "project — branch" → "project")
      -- so the banner shows just the session name, not the trailing detail.
      name = vim.trim((name:gsub('%s*—.*$', '')))
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
          vim.list_extend(fonts, vim.fn.globpath(bundled_font_dir, '*.flf', false, true))
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
    prime_recent_convos()
  end,
})

-- Reload the dashboard, forcing a fresh ASCII-art font. prime_header() reuses
-- the banner cached per session name, so on a reopen the name still matches and
-- the same font sticks. Clearing the cache first makes prime_header re-pick a
-- random figlet font on the next SnacksDashboardOpened.
local function reload_dashboard()
  header_cache = nil
  Snacks.dashboard.open()
end

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

-- Rename the current tmux window to mark it as an AI session, then run the
-- given action (a Vim command string or a function). A no-op outside tmux.
local function ai_session(action)
  return function()
    vim.fn.system { 'tmux', 'rename-window', '📝🤖' }
    if type(action) == 'function' then
      action()
    else
      vim.cmd(action)
    end
  end
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
    get_recent_conversations,
    { icon = '⏳', title = 'Recent Files', section = 'recent_files', cwd = true, indent = 2, padding = 1 },
    { icon = '🤖', key = 'c', desc = 'Claude Code', action = ai_session ':ClaudeCode' },
    { icon = '🥧', key = 'a', desc = 'AI (pi)', action = ai_session ':silent !tmux split-window -h pi' },
    { icon = '📑', key = 'f', desc = 'Files', action = ':GoToFile' },
    { icon = '🔎', key = '/', desc = 'Find Text', action = ':Grep' },
    { icon = '🐙', key = 'i', desc = 'Issue', action = view_branch_issue },
    { icon = '🔀', key = 'p', desc = 'Pull Request', action = view_branch_pr },
    { icon = '🔄', key = 'R', desc = 'Reload Dashboard', action = reload_dashboard },
    { icon = '👋', key = 'q', desc = 'Quit', action = ':qa' },
  },
}
