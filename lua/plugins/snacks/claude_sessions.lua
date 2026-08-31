-- Thin Lua front door onto the shared `claude-sessions` resolver
-- (~/c/claude-code-tools/sessions). That module owns the title cascade
-- (aiTitle → typed prompt → /command — args → first assistant sentence) AND
-- the cwd → ~/.claude/projects/<encoded> path encoding, both of which used to
-- live here as bash/jq and had already drifted between the dashboard and the
-- picker. The status line calls the same TypeScript, so there is now exactly
-- one definition of "what is this session called?".
--
-- Presentation stays with each caller: widths, age strings and icons are per-UI
-- budgets, not shared logic, so titles come back untruncated on purpose.

local M = {}

-- dist/ is gitignored, so the bundle is a locally-built artifact that may simply
-- not be there (fresh clone, post-clean). Every failure here is non-fatal: the
-- dashboard and picker just show no conversations rather than erroring on open.
--   rebuild: cd ~/c/claude-code-tools/sessions && npm install && npm run build
M.bundle = vim.fn.expand '~/c/claude-code-tools/sessions/dist/claude-sessions.mjs'

---Argv listing the sessions for `cwd`, newest first.
---@param cwd string
---@param limit integer? cap the result; omit for all sessions
---@return string[]
function M.list_cmd(cwd, limit)
  local cmd = { 'node', M.bundle, 'list', '--cwd', cwd, '--json' }
  if limit then
    vim.list_extend(cmd, { '--limit', tostring(limit) })
  end
  return cmd
end

---Decode one CLI result into a session array.
---
---The CLI reports its own errors as JSON on stdout with exit 1, so a nonzero
---exit means the process itself failed (missing bundle, no node) and stdout is
---not ours to parse. An unknown project is not an error — it decodes to `{}`.
---@param res vim.SystemCompleted
---@return table[]? sessions nil when the resolver could not be run
function M.decode(res)
  if not res or res.code ~= 0 then
    return nil
  end
  local ok, sessions = pcall(vim.json.decode, res.stdout or '')
  if not ok or type(sessions) ~= 'table' then
    return nil
  end
  return sessions
end

---Blocking variant, for call sites that need items up front (the picker).
---@param cwd string
---@param limit integer?
---@return table[] sessions empty when the resolver is unavailable
function M.list(cwd, limit)
  -- pcall because vim.system raises if `node` itself is not on PATH, and a
  -- missing toolchain should not take the picker down with it.
  local ok, res = pcall(function()
    return vim.system(M.list_cmd(cwd, limit), { text = true }):wait()
  end)
  return (ok and M.decode(res)) or {}
end

return M
