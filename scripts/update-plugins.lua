-- Headless Lazy.nvim plugin update script
-- Usage: nvim --headless -c "luafile scripts/update-plugins.lua"

local function write(s)
  io.write(s)
  io.flush()
end

local function run()
  -- Wait for Lazy to be available
  local ok, lazy = pcall(require, 'lazy')
  if not ok then
    write 'ERROR: Lazy.nvim not available\n'
    vim.cmd 'qa!'
    return
  end

  -- Run update (blocks until complete)
  lazy.update { show = false, wait = true }

  local config = require 'lazy.core.config'
  local plugins = config.plugins

  local updated = {}
  local breaking = {}
  local errors = {}
  local total = 0

  for name, plugin in pairs(plugins) do
    total = total + 1
    local state = plugin._

    -- Check for errors in tasks
    if state.tasks then
      for _, task in ipairs(state.tasks) do
        if task:has_errors() then
          table.insert(errors, { name = name, output = task:output() })
        end
      end
    end

    -- Check if plugin was updated
    if state.updated and state.updated.from and state.updated.to and state.updated.from ~= state.updated.to then
      -- Run git log directly — task:output() returns status messages in headless mode
      local log_output = vim.fn.system {
        'git',
        '-C',
        plugin.dir,
        'log',
        '--pretty=format:%h %s (%cr)',
        '--abbrev-commit',
        '--color=never',
        '--no-show-signature',
        state.updated.from .. '..' .. state.updated.to,
      }

      local lines = {}
      if vim.v.shell_error == 0 and log_output ~= '' then
        for line in log_output:gmatch '[^\n]+' do
          table.insert(lines, line)
        end
      end

      -- Detect breaking changes
      local has_breaking = false
      for _, line in ipairs(lines) do
        if line:find '^%w+ %S+!:' or line:lower():find 'breaking' then
          has_breaking = true
          break
        end
      end

      local entry = {
        name = name,
        from = state.updated.from:sub(1, 7),
        to = state.updated.to:sub(1, 7),
        lines = lines,
      }

      table.insert(updated, entry)
      if has_breaking then
        table.insert(breaking, entry)
      end
    end
  end

  -- Sort by name
  table.sort(updated, function(a, b)
    return a.name < b.name
  end)
  table.sort(breaking, function(a, b)
    return a.name < b.name
  end)

  -- Print report
  write '\n=== Plugin Update Report ===\n'
  write(string.format('Date: %s\n', os.date '%Y-%m-%d %H:%M:%S'))

  if #breaking > 0 then
    write(string.format('\n!!! BREAKING CHANGES (%d) !!!\n', #breaking))
    for _, entry in ipairs(breaking) do
      write(string.format('  %s (%s -> %s)\n', entry.name, entry.from, entry.to))
      for _, line in ipairs(entry.lines) do
        if line:find '^%w+ %S+!:' or line:lower():find 'breaking' then
          write(string.format('    %s  <<<\n', line))
        else
          write(string.format('    %s\n', line))
        end
      end
    end
  end

  if #errors > 0 then
    write(string.format('\n*** ERRORS (%d) ***\n', #errors))
    for _, err in ipairs(errors) do
      write(string.format('  %s: %s\n', err.name, err.output))
    end
  end

  if #updated > 0 then
    write(string.format('\n--- Updated (%d plugins) ---\n', #updated))
    for _, entry in ipairs(updated) do
      write(string.format('  %s (%s -> %s)\n', entry.name, entry.from, entry.to))
      for _, line in ipairs(entry.lines) do
        if line:find '^%w+ %S+!:' or line:lower():find 'breaking' then
          write(string.format('    %s  <<<\n', line))
        else
          write(string.format('    %s\n', line))
        end
      end
    end
  end

  local up_to_date = total - #updated
  write '\n--- Summary ---\n'
  write(string.format('  Total: %d | Updated: %d | Breaking: %d | Errors: %d | Up to date: %d\n\n', total, #updated, #breaking, #errors, up_to_date))

  vim.cmd 'qa!'
end

-- Schedule to run after init is complete
vim.schedule(run)
