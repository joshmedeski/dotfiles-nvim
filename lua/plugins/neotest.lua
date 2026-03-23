return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-neotest/nvim-nio',
    'nvim-lua/plenary.nvim',
    'antoinemadec/FixCursorHold.nvim',
    'nvim-treesitter/nvim-treesitter',
    'marilari88/neotest-vitest',
    'thenbe/neotest-playwright',
    { 'fredrikaverpil/neotest-golang', version = '*' },
    'rcasia/neotest-bash',
  },

  config = function()
    local function has_playwright_config()
      return vim.fn.filereadable(vim.fn.getcwd() .. '/playwright.config.ts') == 1 or vim.fn.filereadable(vim.fn.getcwd() .. '/playwright.config.js') == 1
    end

    ---@diagnostic disable-next-line: missing-fields
    require('neotest').setup {
      adapters = {
        require 'neotest-golang' {
          runner = 'go',
          go_test_args = {
            '-v',
            '-race',
            '-count=1',
            '-coverprofile=' .. vim.fn.getcwd() .. '/coverage.out',
          },
        },
        require('neotest-playwright').adapter {
          options = {
            persist_project_selection = true,
            enable_dynamic_test_discovery = true,
          },
          filter_dir = function(name)
            return name ~= 'node_modules'
          end,
          is_test_file = function(file_path)
            if not has_playwright_config() then
              return false
            end
            return string.match(file_path, '%.spec%.[jt]sx?$') ~= nil or string.match(file_path, '%.test%.[jt]sx?$') ~= nil
          end,
        },
        require 'neotest-vitest' {
          args = { '--coverage' },
          is_test_file = function(file_path)
            if has_playwright_config() then
              return false
            end
            return string.match(file_path, '%.spec%.[jt]sx?$') ~= nil
              or string.match(file_path, '%.test%.[jt]sx?$') ~= nil
              or string.match(file_path, '__tests__') ~= nil
          end,
        },
        require 'neotest-bash' {
          args = { '--coverage', '--coverage-paths', 'bin', '--coverage-report', vim.fn.getcwd() .. '/coverage/lcov.info' },
        },
      },
    }
  end,

  keys = {
    { '<leader>ta', "<cmd>lua require('neotest').run.attach()<cr>", desc = 'Attach to the nearest test' },
    { '<leader>tl', "<cmd>lua require('neotest').run.run_last()<cr>", desc = 'Toggle Test Summary' },
    { '<leader>to', "<cmd>lua require('neotest').output_panel.toggle()<cr>", desc = 'Toggle Test Output Panel' },
    { '<leader>tp', "<cmd>lua require('neotest').run.stop()<cr>", desc = 'Stop the nearest test' },
    { '<leader>ts', "<cmd>lua require('neotest').summary.toggle()<cr>", desc = 'Toggle Test Summary' },
    { '<leader>tt', "<cmd>lua require('neotest').run.run()<cr>", desc = 'Run the nearest test' },
    {
      '<leader>tT',
      "<cmd>lua require('neotest').run.run(vim.fn.expand('%'))<cr>",
      desc = 'Run test the current file',
    },
    {
      '<leader>td',
      function()
        require('neotest').run.run { suite = false, strategy = 'dap' }
      end,
      desc = 'Debug nearest test',
    },
  },
}
