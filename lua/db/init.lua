local Split = require 'nui.split'
local Job = require 'plenary.job'
local pickers = require 'telescope.pickers'
local finders = require 'telescope.finders'
local conf = require('telescope.config').values
local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'

local open_picker = function(records, opts)
  opts = opts or {}
  local picker_opts = require('telescope.themes').get_dropdown(opts.picker or {})

  pickers
    .new(picker_opts, {
      prompt_title = opts.title or 'Databases',
      finder = finders.new_table {
        results = records,
        entry_maker = opts.entry_maker or nil,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)

          if opts.callback then
            opts.callback(action_state.get_selected_entry())
          end
        end)
        return true
      end,
      sorter = conf.generic_sorter(opts),
    })
    :find()
end

local M = {}

M.connId = nil

M.databases = nil

M.active_connections = {}

M.connections = {}

M.execute = function(opts, cb, onerr)
  local args = { '-h', M.active_connections[M.connId].host, '--protocol', 'tcp', '--binary-as-hex', '-e', opts.sql }
  if M.active_connections[M.connId].database ~= nil then
    table.insert(args, '--database')
    table.insert(args, M.active_connections[M.connId].database)
  end

  if M.active_connections[M.connId].password ~= nil then
    table.insert(args, '-p' .. M.active_connections[M.connId].password)
  end

  if M.active_connections[M.connId].user ~= nil then
    table.insert(args, '-u' .. M.active_connections[M.connId].user)
  end

  if opts.table == nil or opts.table == true then
    table.insert(args, '--table')
  end

  if opts.columns ~= nil and opts.columns == false then
    table.insert(args, '--skip-column-names')
  end

  Job:new({
    command = 'mysql',
    args = args,
    cwd = vim.fn.getcwd(),
    on_exit = function(j, return_val)
      if return_val == 0 then
        cb(j:result())
      else
        onerr(j:stderr_result())
      end
    end,
  }):start()
end

M.open = function(opts)
  opts = opts or {}
  local pickers_opts = require('telescope.themes').get_dropdown(opts.picker or {})
  M.parent_win = vim.api.nvim_get_current_win()

  if #M.connections == 0 then
    vim.notify 'Add connections first'
    return
  end

  open_picker(M.connections, {
    title = 'Connections',
    entry_maker = function(entry)
      return {
        value = entry,
        display = entry.name,
        ordinal = entry.name,
      }
    end,
    callback = function(selection)
      M.active_connections[selection.value.name] = selection.value
      M.connId = selection.value.name

      if selection.value.database ~= nil then
        M.create_buffers()
      else
        M.pick_database()
      end
    end,
  })
end

M.pick_database = function(opts)
  local callback = function(entry)
    M.active_connections[M.connId].database = entry[1]
    M.create_buffers()
  end

  if M.active_connections[M.connId].databases ~= nil then
    open_picker(M.active_connections[M.connId].databases, { callback = callback })
    return
  end

  M.execute(
    { sql = 'show databases;', columns = false, table = false },
    vim.schedule_wrap(function(databases)
      M.active_connections[M.connId].databases = databases
      open_picker(databases, { callback = callback })
    end)
  )
end

M.open_tables = function()
  if M.connId == nil or M.active_connections[M.connId].database == nil then
    vim.notify 'Please connect to a server and a database'
    return
  end

  M.execute(
    { sql = 'show tables', columns = false, table = false },
    vim.schedule_wrap(function(tables)
      M.active_connections[M.connId].tables = tables
      open_picker(tables, {
        callback = function(entry)
          if M.query_split.bufnr and vim.api.nvim_buf_is_valid(M.query_split.bufnr) then
            local line_count = vim.api.nvim_buf_line_count(M.query_split.bufnr)
            vim.api.nvim_buf_set_lines(M.query_split.bufnr, line_count, line_count, false, { 'select * from ' .. entry[1] .. ' limit 10;' })
            vim.api.nvim_win_set_cursor(M.query_split.win, { line_count + 1, 1 })
          end
        end,
      })
    end)
  )
end

M.open_active_connections = function()
  local count = 0
  local connections = {}
  for _, conn in pairs(M.active_connections) do
    count = count + 1
    if conn.name == M.connId then
      conn.name = conn.name .. ' (active)'
    end
    table.insert(connections, conn.name)
  end
  if count == 0 then
    vim.notify 'There are no active connections'
    return
  end

  open_picker(connections, {
    callback = function(entry)
      M.connId = entry[1]
    end,
  })
end

M.create_buffers = function()
  if M.query_split == nil then
    M.query_split = {
      bufnr = 0,
      win = M.parent_win,
      filename = M.get_data_folder() .. M.connId:lower() .. '.sql',
    }
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == M.query_split.filename then
        M.query_split.bufnr = buf
      end
    end
    M.query_split.bufnr = M.query_split.bufnr or vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_option_value('swapfile', false, { buf = M.query_split.bufnr })
    vim.api.nvim_set_option_value('buftype', '', { buf = M.query_split.bufnr })
    vim.api.nvim_buf_set_name(M.query_split.bufnr, M.query_split.filename)
    vim.api.nvim_win_set_buf(M.query_split.win, M.query_split.bufnr)

    if not vim.api.nvim_get_option_value('modified', { buf = M.query_split.bufnr }) then
      vim.api.nvim_win_call(M.query_split.win, function()
        vim.api.nvim_command 'silent e'
      end)
    end
  else
    if not vim.api.nvim_win_is_valid(M.query_split.win) then
      M.query_split = nil
      M.create_buffers()
      return
    end
    vim.api.nvim_set_current_win(M.query_split.win)
    vim.api.nvim_set_current_buf(M.query_split.bufnr)
  end
end

M.run_query = function(lines)
  if not M.connId then
    vim.notify 'Connect to a database first'
    return
  end

  if M.output_split ~= nil then
    M.output_split:unmount()
  end

  M.output_split = Split {
    relative = 'win',
    position = 'bottom',
    size = '20%',
    win_options = {
      wrap = false,
    },
  }

  M.execute(
    { sql = table.concat(lines, '\n') },
    vim.schedule_wrap(function(output)
      M.output_split:mount()
      vim.api.nvim_buf_set_lines(M.output_split.bufnr, 0, -1, false, output)
      vim.api.nvim_set_option_value('modified', false, { buf = M.output_split.bufnr })
    end),
    vim.schedule_wrap(function(err)
      vim.print(vim.inspect(err))
    end)
  )
end

M.get_data_folder = function()
  return vim.fn.stdpath 'data' .. '/mysql/'
end

M.init = function()
  local folder = M.get_data_folder()
  if not vim.loop.fs_stat(folder) then
    vim.fn.system { 'mkdir', folder }
  end
end

M.setup = function(opts)
  opts = opts or {}
  M.connections = opts.connections or {}

  local au = vim.api.nvim_create_augroup('mysql', {})

  vim.api.nvim_create_autocmd('BufWritePost', {
    pattern = { '*.sql' },
    group = au,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      M.run_query(lines)
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    pattern = { '*.sql' },
    group = au,
    callback = function(args)
      vim.keymap.set('n', '<CR>', function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        M.run_query(lines)
      end, { buffer = args.buf })

      vim.keymap.set('v', '<CR>', function()
        local selected_lines = vim.fn.getregion(vim.fn.getpos 'v', vim.fn.getpos '.', { type = vim.fn.mode() })
        M.run_query(selected_lines)
      end, { buffer = args.buf })
    end,
  })
end

return M
