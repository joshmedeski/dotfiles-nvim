return {
  {
    'lewis6991/gitsigns.nvim',
    enabled = true,
    event = { 'BufReadPost', 'BufNewFile' },
    opts = {
      signs = {
        add = { text = '' },
        change = { text = '' },
        delete = { text = '' },
        topdelete = { text = '' },
        changedelete = { text = '' },
        untracked = { text = '' },
      },
      on_attach = function(bufnr)
        local gitsigns = require 'gitsigns'

        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        -- Navigation
        map('n', ']h', function()
          if vim.wo.diff then
            vim.cmd.normal { ']c', bang = true }
          else
            gitsigns.nav_hunk 'next'
            vim.cmd 'normal! zt'
          end
        end, { desc = 'Next git [h]unk' })

        map('n', '[h', function()
          if vim.wo.diff then
            vim.cmd.normal { '[c', bang = true }
          else
            gitsigns.nav_hunk 'prev'
            vim.cmd 'normal! zt'
          end
        end, { desc = 'Previous git [h]unk' })

        -- Actions
        -- visual mode
        map('v', '<leader>hs', function()
          gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'git [s]tage hunk' })
        map('v', '<leader>hr', function()
          gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'git [r]eset hunk' })
        -- normal mode
        map('n', '<leader>hs', gitsigns.stage_hunk, { desc = 'git [s]tage hunk' })
        map('n', '<leader>hr', gitsigns.reset_hunk, { desc = 'git [r]eset hunk' })
        map('n', '<leader>hS', gitsigns.stage_buffer, { desc = 'git [S]tage buffer' })
        map('n', '<leader>hu', gitsigns.stage_hunk, { desc = 'git [u]ndo stage hunk' })
        map('n', '<leader>hR', gitsigns.reset_buffer, { desc = 'git [R]eset buffer' })
        map('n', '<leader>hp', gitsigns.preview_hunk_inline, { desc = 'git [p]review hunk (inline)' })
        map('n', '<leader>hP', gitsigns.preview_hunk, { desc = 'git [P]review hunk' })
        map('n', '<leader>hb', gitsigns.blame_line, { desc = 'git [b]lame line' })
        map('n', '<leader>hd', gitsigns.diffthis, { desc = 'git [d]iff against index' })
        map('n', '<leader>hD', function()
          gitsigns.diffthis '@'
        end, { desc = 'git [D]iff against last commit' })
        -- Toggles
        map('n', '<leader>tb', gitsigns.toggle_current_line_blame, { desc = '[T]oggle git show [b]lame line' })
        map('n', '<leader>tD', gitsigns.preview_hunk_inline, { desc = '[T]oggle git show [D]eleted' })

        -- Jump to first hunk on file open
        local jumped = false
        vim.api.nvim_create_autocmd('User', {
          pattern = 'GitSignsUpdate',
          callback = function(args)
            if jumped or args.buf ~= bufnr then
              return
            end
            jumped = true
            -- Defer so the window has finished drawing before we scroll.
            -- `nav_hunk('first')` is async and lands on the hunk's *end*, so
            -- read the first hunk directly and jump to its start instead.
            vim.schedule(function()
              local hunks = gitsigns.get_hunks(bufnr)
              if not hunks or #hunks == 0 then
                return
              end
              local win = vim.fn.bufwinid(bufnr)
              if win == -1 then
                return
              end
              local line = math.max(math.min(hunks[1].added.start, vim.api.nvim_buf_line_count(bufnr)), 1)
              vim.api.nvim_win_set_cursor(win, { line, 0 })
              vim.api.nvim_win_call(win, function()
                vim.cmd 'normal! zt'
              end)
            end)
          end,
        })
      end,
    },
  },
}
