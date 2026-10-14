return {
  'ThePrimeagen/refactoring.nvim',
  opts = {},
  keys = {
    { '<leader>re', '<cmd>lua require("refactoring").select_refactor()<CR>', desc = 'Refactor' },
  },
}
