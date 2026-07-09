-- fff's prebuilt binary uses the zlob walker, which only reads .gitignore files
-- inside the walked tree — it does not climb to the git root. Rooting the walk at
-- the git top-level puts the repo-root .gitignore in scope so live grep honors it
-- even when nvim is opened in a monorepo subdirectory. Falls back to cwd outside a repo.
local function grep_root()
  return vim.fs.root(vim.uv.cwd(), '.git') or vim.uv.cwd()
end

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
        require('fff').live_grep { cwd = grep_root() }
      end,
      desc = 'Grep',
    },
    {
      '<leader>sg',
      function()
        require('fff').live_grep { cwd = grep_root() }
      end,
      desc = 'Grep',
    },
    {
      '<leader>sw',
      function()
        require('fff').live_grep { cwd = grep_root(), query = vim.fn.expand '<cword>' }
      end,
      desc = 'Visual selection or word',
      mode = { 'n', 'x' },
    },
  },
}
