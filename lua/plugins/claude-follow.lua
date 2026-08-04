return {
  -- Local plugin: no remote yet, so point lazy at the checkout directly.
  dir = vim.fn.stdpath 'data' .. '/lazy/claude-follow.nvim',
  -- Loads at startup so setup() publishes the discovery record a hook needs to
  -- find this instance when Claude runs outside Neovim.
  event = 'VeryLazy',
  opts = {},
}
