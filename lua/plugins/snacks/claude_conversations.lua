-- Snacks picker over this project's past Claude Code conversations, read from
-- disk (~/.claude/projects/<encoded-cwd>/*.jsonl) so it works whether or not a
-- Claude terminal is running. Fuzzy-matches on session title, previews the
-- recent message exchange, and resumes the selection in a tmux split (same
-- action as the dashboard's Recent Conversations section).
--
-- Locating and titling those sessions is the shared resolver's job; the preview
-- below stays local because it renders the transcript body, not the title.

local claude_sessions = require 'plugins.snacks.claude_sessions'

-- Render the recent exchange from one session file ($1) for the preview pane:
-- plain-text user/assistant messages, tool noise stripped, newest at the bottom.
local preview_cmd = [[
jq -r 'select(.type == "user" or .type == "assistant")
  | (.message.content | if type == "string" then . else (map(select(.type == "text").text) | join("\n")) end) as $t
  | select($t != null and $t != "")
  | "── \(.type) ──\n\($t)\n"' "$1" 2>/dev/null | tail -120
]]

-- This project's sessions, newest-first, as picker items. One resolver call
-- replaces the old loop that spawned a bash+jq pipeline per transcript, so
-- open cost no longer scales with the number of sessions. It also fixes the
-- folder this reads from: the encoding lived here as gsub('[/.]', '-'), which
-- missed characters like '_' and silently pointed at a directory that does not
-- exist — the resolver owns that mapping now.
local function find_sessions()
  local items = {}
  for idx, session in ipairs(claude_sessions.list(vim.fn.getcwd())) do
    local title = session.title ~= '' and session.title or ('Untitled (' .. session.id:sub(1, 8) .. ')')
    items[#items + 1] = {
      idx = idx,
      text = title,
      title = title,
      id = session.id,
      file = session.path,
      mtime = session.mtime,
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
