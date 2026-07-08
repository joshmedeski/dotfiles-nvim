-- Snacks picker over this project's past Claude Code conversations, read from
-- disk (~/.claude/projects/<encoded-cwd>/*.jsonl) so it works whether or not a
-- Claude terminal is running. Fuzzy-matches on session title, previews the
-- recent message exchange, and resumes the selection in a tmux split (same
-- action as the dashboard's Recent Conversations section).

-- Map the current working directory to its Claude Code project folder
-- (cwd with '/' and '.' replaced by '-').
local function claude_project_dir()
  local encoded = vim.fn.getcwd():gsub('[/.]', '-')
  return vim.fs.joinpath(vim.fn.expand '~/.claude/projects', encoded)
end

-- Pull the latest aiTitle from one session file ($1). grep narrows to the
-- ai-title lines first so jq never parses multi-megabyte transcripts.
local title_cmd = [[grep '"type":"ai-title"' "$1" 2>/dev/null | tail -1 | jq -r '.aiTitle // ""' 2>/dev/null]]

-- Render the recent exchange from one session file ($1) for the preview pane:
-- plain-text user/assistant messages, tool noise stripped, newest at the bottom.
local preview_cmd = [[
jq -r 'select(.type == "user" or .type == "assistant")
  | (.message.content | if type == "string" then . else (map(select(.type == "text").text) | join("\n")) end) as $t
  | select($t != null and $t != "")
  | "── \(.type) ──\n\($t)\n"' "$1" 2>/dev/null | tail -120
]]

-- List this project's sessions newest-first as picker items. Titles come from
-- a single blocking pass over the files; grep+jq keep it cheap enough for the
-- picker-open path.
local function find_sessions()
  local dir = claude_project_dir()
  local files = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == 'file' and name:match '%.jsonl$' then
      local path = vim.fs.joinpath(dir, name)
      local stat = vim.uv.fs_stat(path)
      if stat then
        files[#files + 1] = { path = path, id = name:gsub('%.jsonl$', ''), mtime = stat.mtime.sec }
      end
    end
  end
  table.sort(files, function(a, b)
    return a.mtime > b.mtime
  end)
  local items = {}
  for idx, f in ipairs(files) do
    local title = vim.trim(vim.fn.system { 'bash', '-c', title_cmd, 'claude_title', f.path })
    if title == '' then
      title = 'Untitled (' .. f.id:sub(1, 8) .. ')'
    end
    items[#items + 1] = {
      idx = idx,
      text = title,
      title = title,
      id = f.id,
      file = f.path,
      mtime = f.mtime,
      score = 0,
    }
  end
  return items
end

-- "3h ago"-style age for the list column.
local function age(mtime)
  local s = os.time() - mtime
  if s < 3600 then
    return math.max(1, math.floor(s / 60)) .. 'm ago'
  elseif s < 86400 then
    return math.floor(s / 3600) .. 'h ago'
  end
  return math.floor(s / 86400) .. 'd ago'
end

return function()
  local cwd = vim.fn.getcwd()
  Snacks.picker.pick {
    title = 'Claude Conversations',
    items = find_sessions(),
    format = function(item)
      return {
        { '💬 ', virtual = true },
        { item.title, 'SnacksPickerLabel' },
        { ' ' .. age(item.mtime), 'SnacksPickerComment' },
      }
    end,
    preview = function(ctx)
      -- Parse the transcript once per item, then cache; large sessions make
      -- jq too slow to re-run on every list movement.
      if not ctx.item.preview_lines then
        ctx.item.preview_lines = vim.fn.systemlist { 'bash', '-c', preview_cmd, 'claude_preview', ctx.item.file }
      end
      ctx.preview:set_lines(ctx.item.preview_lines)
      ctx.preview:set_title(ctx.item.title)
      return true
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      if vim.env.TMUX then
        vim.fn.system(('tmux split-window -h -c %s claude --resume %s'):format(vim.fn.shellescape(cwd), item.id))
      else
        vim.notify('Not inside tmux; run: claude --resume ' .. item.id, vim.log.levels.WARN)
      end
    end,
  }
end
