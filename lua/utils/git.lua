---
-- Shared git helpers used from more than one place (keymaps and the snacks
-- dashboard), so the logic lives in exactly one spot.
local M = {}

-- Open every file this branch changed (vs. origin/main) as its own buffer
function M.open_branch_changes()
  -- run git from the repo root so the returned paths line up with it
  local root = vim.fs.root(vim.uv.cwd(), '.git')
  if not root then
    vim.notify('Not in a git repository', vim.log.levels.WARN)
    return
  end

  -- prefer origin/main, fall back to origin/master for older repos
  local base
  for _, ref in ipairs { 'origin/main', 'origin/master' } do
    vim.fn.system { 'git', '-C', root, 'rev-parse', '--verify', '--quiet', ref }
    if vim.v.shell_error == 0 then
      base = ref
      break
    end
  end
  if not base then
    vim.notify('No origin/main or origin/master to compare against', vim.log.levels.WARN)
    return
  end

  -- --merge-base diffs against the fork point, so commits landed on main after
  -- branching don't show up; --diff-filter=d drops files deleted on this branch
  local files = vim.fn.systemlist { 'git', '-C', root, 'diff', '--name-only', '--diff-filter=d', '--merge-base', base }
  if vim.v.shell_error ~= 0 then
    vim.notify('git diff failed: ' .. table.concat(files, '\n'), vim.log.levels.ERROR)
    return
  end

  local first
  for _, file in ipairs(files) do
    -- bufadd creates the buffer without loading it; buflisted makes it show up
    -- in :ls and in the <Tab>/<S-Tab> buffer cycle
    local buf = vim.fn.bufadd(root .. '/' .. file)
    vim.bo[buf].buflisted = true
    first = first or buf
  end

  if not first then
    vim.notify('No changes vs. ' .. base)
    return
  end

  vim.api.nvim_set_current_buf(first)
  vim.notify(('Opened %d changed file(s) vs. %s'):format(#files, base))
end

return M
