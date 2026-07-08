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

-- Derive a display label from one session file ($1), falling back through
-- progressively rougher signals so command/skill-started sessions (which never
-- get an aiTitle) still read as something meaningful instead of "Untitled".
-- grep prefilters keep jq off multi-megabyte transcripts on the cheap paths.
--   1. aiTitle          - Claude's generated title (natural-language sessions)
--   2. /command — args  - first slash command / skill invocation (skips /clear)
--   3. last typed prompt
--   4. first assistant sentence
local label_cmd = [==[
f="$1"

t=$(grep '"type":"ai-title"' "$f" 2>/dev/null | tail -1 | jq -r '.aiTitle // empty' 2>/dev/null)
if [ -n "$t" ]; then printf '%s' "$t"; exit 0; fi

while IFS= read -r line; do
  c=$(printf '%s' "$line" | jq -r '.message.content | if type == "string" then . else (map(select(.type == "text").text) | join("\n")) end' 2>/dev/null)
  n=$(printf '%s' "$c" | sed -n 's|.*<command-name>[[:space:]]*/*\([^<[:space:]]*\).*|\1|p' | head -1)
  [ -z "$n" ] && continue
  [ "$n" = "clear" ] && continue
  a=$(printf '%s' "$c" | sed -n 's|.*<command-args>[[:space:]]*\([^<]*\)</command-args>.*|\1|p' | head -1 | sed 's/[[:space:]]*$//')
  if [ -n "$a" ]; then printf '/%s — %s' "$n" "$a" | tr '\n' ' ' | cut -c1-80; else printf '/%s' "$n"; fi
  exit 0
done < <(grep '<command-name>' "$f" 2>/dev/null)

lp=$(grep '"type":"last-prompt"' "$f" 2>/dev/null | jq -r '.lastPrompt // empty' 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1)
if [ -n "$lp" ]; then printf '%s' "$lp" | tr '\n' ' ' | cut -c1-80; exit 0; fi

at=$(jq -r 'select(.type == "assistant") | (.message.content | if type == "array" then (map(select(.type == "text").text) | join(" ")) else "" end)' "$f" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)
if [ -n "$at" ]; then printf '%s' "$at" | tr '\n' ' ' | cut -c1-80; exit 0; fi
]==]

-- Render the recent exchange from one session file ($1) for the preview pane:
-- plain-text user/assistant messages, tool noise stripped, newest at the bottom.
local preview_cmd = [[
jq -r 'select(.type == "user" or .type == "assistant")
  | (.message.content | if type == "string" then . else (map(select(.type == "text").text) | join("\n")) end) as $t
  | select($t != null and $t != "")
  | "── \(.type) ──\n\($t)\n"' "$1" 2>/dev/null | tail -120
]]

-- List this project's sessions newest-first as picker items. Labels come from
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
    local title = vim.trim(vim.fn.system { 'bash', '-c', label_cmd, 'claude_label', f.path })
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
