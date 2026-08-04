-- Find And Replace plugin for neovim
return {
  'MagicDuck/grug-far.nvim',
  -- Match navigation recenters the source window by default; keep the view put.
  opts = { headerMaxWidth = 80, centerOnNavigation = false },
  cmd = 'GrugFar',
  keys = {
    {
      '<leader>sr',
      function()
        local grug = require 'grug-far'
        local ext = vim.bo.buftype == '' and vim.fn.expand '%:e'
        grug.open {
          transient = true,
          prefills = {
            filesFilter = ext and ext ~= '' and '*.' .. ext or nil,
          },
        }
      end,
      mode = { 'n', 'v' },
      desc = 'Search and Replace',
    },
  },
}
