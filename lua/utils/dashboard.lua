-- Single entry point for opening the snacks dashboard.
--
-- snacks reuses one fixed augroup name ("snacks_dashboard") for every dashboard
-- instance, so all instances share the same augroup id. Yet each dashboard
-- *buffer* installs its own buffer-local autocmd that unconditionally runs
-- `nvim_del_augroup_by_id` on that shared id when the buffer is wiped (no pcall).
-- With 2+ dashboard buffers alive at once, the second one to be wiped deletes an
-- already-deleted augroup and throws `E367: No such group: "--Deleted--"`.
--
-- We open the dashboard from several places (startup, <leader>H, the "reopen on
-- last buffer closed" autocmd, and the reload action), and each call leaves a
-- fresh dashboard buffer behind, so the buffers accumulate. Wiping any lingering
-- dashboard buffer before opening keeps exactly one alive, so its augroup is
-- always freshly created and deleted exactly once.
local M = {}

function M.open()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'snacks_dashboard' then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  return Snacks.dashboard.open()
end

return M
