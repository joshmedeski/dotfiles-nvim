return {
  'dmtrKovalenko/fff.nvim',
  lazy = false,
  build = function()
    require('fff.download').download_or_build_binary()
  end,
  opts = {
    layout = {
      prompt_position = 'top',
    },
  },
  keys = {
    {
      '<leader>ff',
      function()
        require('fff').find_files()
      end,
      desc = 'Find Files',
    },
    {
      '<leader>fg',
      function()
        require('fff').find_files()
      end,
      desc = 'Find Git Files',
    },
    {
      '<leader>fc',
      function()
        require('fff').find_files_in_dir(vim.fn.stdpath 'config')
      end,
      desc = 'Find Config File',
    },
    {
      '<leader>/',
      function()
        require('fff').live_grep()
      end,
      desc = 'Grep',
    },
    {
      '<leader>sg',
      function()
        require('fff').live_grep()
      end,
      desc = 'Grep',
    },
    {
      '<leader>sw',
      function()
        require('fff').live_grep { query = vim.fn.expand '<cword>' }
      end,
      desc = 'Visual selection or word',
      mode = { 'n', 'x' },
    },
  },
}
