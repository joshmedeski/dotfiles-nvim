-- Shared bash function that derives a display label from one Claude Code
-- session file ($1). Required by both the dashboard's Recent Conversations
-- section (dashboard.lua) and the Claude Conversations picker
-- (claude_conversations.lua) so the two label the same session identically and
-- can never drift apart.
--
-- Returns a `claude_label()` shell function definition. Call sites source this
-- string then invoke `claude_label "<file>"`. It uses `return` (not `exit`) so
-- callers can loop over several files in one bash invocation.
--
-- The cascade falls through progressively rougher signals so command/skill-
-- started sessions (which never get an aiTitle) still read as something
-- meaningful instead of "Untitled". grep prefilters keep jq off multi-megabyte
-- transcripts on the cheap paths.
--   1. aiTitle          - Claude's generated title (natural-language sessions)
--   2. /command — args  - first slash command / skill invocation (skips /clear)
--   3. last typed prompt
--   4. first assistant sentence
return [==[
claude_label() {
  f="$1"

  t=$(grep '"type":"ai-title"' "$f" 2>/dev/null | tail -1 | jq -r '.aiTitle // empty' 2>/dev/null)
  if [ -n "$t" ]; then printf '%s' "$t"; return 0; fi

  while IFS= read -r line; do
    c=$(printf '%s' "$line" | jq -r '.message.content | if type == "string" then . else (map(select(.type == "text").text) | join("\n")) end' 2>/dev/null)
    n=$(printf '%s' "$c" | sed -n 's|.*<command-name>[[:space:]]*/*\([^<[:space:]]*\).*|\1|p' | head -1)
    [ -z "$n" ] && continue
    [ "$n" = "clear" ] && continue
    a=$(printf '%s' "$c" | sed -n 's|.*<command-args>[[:space:]]*\([^<]*\)</command-args>.*|\1|p' | head -1 | sed 's/[[:space:]]*$//')
    if [ -n "$a" ]; then printf '/%s — %s' "$n" "$a" | tr '\n' ' ' | cut -c1-80; else printf '/%s' "$n"; fi
    return 0
  done < <(grep '<command-name>' "$f" 2>/dev/null)

  lp=$(grep '"type":"last-prompt"' "$f" 2>/dev/null | jq -r '.lastPrompt // empty' 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1)
  if [ -n "$lp" ]; then printf '%s' "$lp" | tr '\n' ' ' | cut -c1-80; return 0; fi

  at=$(jq -r 'select(.type == "assistant") | (.message.content | if type == "array" then (map(select(.type == "text").text) | join(" ")) else "" end)' "$f" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)
  if [ -n "$at" ]; then printf '%s' "$at" | tr '\n' ' ' | cut -c1-80; return 0; fi
}
]==]
