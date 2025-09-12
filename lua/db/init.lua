local Split = require 'nui.split'
local Job = require 'plenary.job'
local pickers = require 'telescope.pickers'
local finders = require 'telescope.finders'
local conf = require('telescope.config').values
local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'

local utils = require 'db.utils'
local history = require 'db.history'

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
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)

          if opts.callback then
            opts.callback(action_state.get_selected_entry())
          end
        end)

        if opts.maps ~= nil then
          for _, value in ipairs(opts.maps) do
            map(value[1], value[2], function()
              value[3](prompt_bufnr)
            end, value[4] or {})
          end
        end
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

M.use_icons = true

M.execute = function(sql, opts)
  opts = opts or {}
  if not vim.fn.executable 'mysql' and opts.error then
    opts.error { 'Command `mysql` was not executable' }
    return
  end

  local args = { '-h', M.active_connections[M.connId].host, '--protocol', 'tcp', '--binary-as-hex', '-e', sql }
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
        if opts.success then
          opts.success(j:result())
        end
        return
      end

      if opts.error then
        opts.error(j:stderr_result())
      end
    end,
  }):start()

  history.add(M.connId, sql)
end

M.open = function(opts)
  opts = opts or {}
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

M.pick_database = function()
  local callback = function(entry)
    M.active_connections[M.connId].database = entry[1]
    M.create_buffers()
  end

  if M.active_connections[M.connId].databases ~= nil then
    open_picker(M.active_connections[M.connId].databases, { callback = callback })
    return
  end

  M.execute('show databases;', {
    columns = false,
    table = false,
    success = vim.schedule_wrap(function(databases)
      M.active_connections[M.connId].databases = databases
      open_picker(databases, { callback = callback })
    end),
  })
end

M.open_tables = function()
  if M.connId == nil or M.active_connections[M.connId].database == nil then
    vim.notify 'Please connect to a server and a database'
    return
  end

  M.execute('show tables;', {
    columns = false,
    table = false,
    success = vim.schedule_wrap(function(tables)
      M.active_connections[M.connId].tables = tables
      open_picker(tables, {
        title = 'Tables',
        callback = function(entry)
          if M.query_split.bufnr and vim.api.nvim_buf_is_valid(M.query_split.bufnr) then
            local line_count = vim.api.nvim_buf_line_count(M.query_split.bufnr)
            local query = { 'select * from ' .. entry[1] .. ' limit 10;' }
            vim.api.nvim_buf_set_lines(M.query_split.bufnr, line_count, line_count, false, query)
            M.run_query(query)
          end
        end,
        maps = {
          {
            'i',
            '<C-i>',
            vim.schedule_wrap(function(prompt_bufnr)
              actions.close(prompt_bufnr)
              local table = action_state.get_selected_entry()[1]
              M.show_table_information(table)
            end),
          },
        },
      })
    end),
  })
end

M.show_table_information = function(table)
  local query = string.format(
    'desc %s; select concat("└─ ", index_name, " (", column_name, ") using ", index_type, " ", if(non_unique=0, "UNIQUE", "")) as "Indexes:" from information_schema.statistics where table_name="%s" and table_schema="%s";',
    table,
    table,
    M.active_connections[M.connId].database
  )
  M.execute(query, {
    success = vim.schedule_wrap(function(info)
      local split = Split {}
      split:mount()
      local header = {
        '+' .. string.rep('-', info[1]:len() - 2) .. '+',
        '|' .. 'Table: ' .. table .. string.rep(' ', info[1]:len() - table:len() - 7 - 2) .. '|',
      }
      vim.api.nvim_buf_set_lines(split.bufnr, 0, -1, false, header)
      vim.api.nvim_buf_set_lines(split.bufnr, -1, -1, false, info)
    end),
    error = vim.schedule_wrap(function(err)
      vim.print(vim.inspect(err))
    end),
  })
end

M.open_active_connections = function()
  local count = 0
  local connections = {}
  for _, conn in pairs(M.active_connections) do
    count = count + 1
    local entry = { name = conn.name, display = conn.name, ordinal = conn.name }
    if conn.name == M.connId then
      entry.display = conn.name .. ' (active)'
    end
    table.insert(connections, entry)
  end
  if count == 0 then
    vim.notify 'There are no active connections'
    return
  end

  open_picker(connections, {
    entry_maker = function(entry)
      return {
        value = entry,
        display = entry.display,
        ordinal = entry.name,
      }
    end,
    callback = function(entry)
      M.connId = entry.value.name
    end,
  })
end

M.create_buffers = function()
  if M.query_split == nil then
    M.query_split = {
      bufnr = 0,
      win = M.parent_win,
      filename = utils.get_data_path(utils.slug(M.connId:lower()) .. '.sql'),
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
    enter = false,
  }

  M.execute(table.concat(lines, '\n'), {
    success = vim.schedule_wrap(function(output)
      M.output_split:mount()
      vim.api.nvim_buf_set_lines(M.output_split.bufnr, 0, -1, false, output)
      vim.api.nvim_set_option_value('modified', false, { buf = M.output_split.bufnr })
    end),
    error = vim.schedule_wrap(function(err)
      vim.print(vim.inspect(err))
    end),
  })
end

M.init = function()
  utils.get_data_path()
end

M.setup = function(opts)
  opts = opts or {}
  M.connections = opts.connections or {}

  if opts.use_icons ~= nil then
    M.use_icons = opts.use_icons
  end

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

M.connection_statusline = function()
  if M.connId == nil then
    return ''
  end

  if M.use_icons then
    return string.format('󱘖 %s', M.connId)
  end

  return M.connId
end

M.database_statusline = function()
  if not M.connId or not M.active_connections[M.connId] then
    return ''
  end

  if M.use_icons then
    return string.format('󰆼 %s', M.active_connections[M.connId].database)
  end

  return M.active_connections[M.connId].database
end

M.open_history = function()
  history.open(M.connId)
end

return M
