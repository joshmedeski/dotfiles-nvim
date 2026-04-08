return {
  'ThePrimeagen/refactoring.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  opts = {},
  keys = {
    { '<leader>re', '<cmd>lua require("refactoring").select_refactor()<CR>', desc = 'Refactor' },
  },
}
