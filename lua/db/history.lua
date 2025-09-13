local NuiTree = require 'nui.tree'
local NuiLine = require 'nui.line'
local Split = require 'nui.split'
local utils = require 'db.utils'
local async = require 'plenary.async'

local M = {}

M.histories = {}

M.active_tab = 'schema'

M.starting_index = 2

M.open = function(connId)
  if not M.is_valid() then
    M.split = Split {
      relative = 'editor',
      position = 'left',
      size = '20%',
      buf_options = {
        filetype = 'mysql',
      },
      win_options = {
        linebreak = true,
        list = false,
      },
    }
  end

  M.split:show()

  M.render(connId)

  vim.api.nvim_buf_set_name(M.split.bufnr, 'db.history')
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(M.split.winid),
    callback = function()
      if vim.api.nvim_buf_is_valid(M.split.bufnr) then
        vim.api.nvim_buf_delete(M.split.bufnr, { force = true })
      end
    end,
  })

  local map_options = { noremap = true, nowait = true }

  M.split:map('n', 'h', function()
    M.active_tab = 'history'
    M.render(connId, function()
      vim.api.nvim_set_option_value('filetype', 'mysql', { buf = M.split.bufnr })
    end)
  end, map_options)

  M.split:map('n', 's', function()
    M.active_tab = 'schema'
    M.render(connId)
  end, map_options)

  M.split:map('n', 'q', function()
    M.split:unmount()
  end, map_options)
end

M.render = function(connId, callback)
  M.unlock_buffer()
  M.render_menu()
  async.run(function()
    if M.active_tab == 'schema' then
      M.render_schema(connId)
    else
      M.render_history(connId)
    end
  end, function()
    M.lock_buffer()
    if callback then
      callback()
    end
  end)
end

M.render_menu = function()
  local menu = { schema = '  Schema [s]  ', history = '  History [h]  ' }
  local line = menu.schema .. menu.history
  local width = vim.api.nvim_win_get_width(M.split.winid) - line:len() - vim.wo.numberwidth - 2

  vim.api.nvim_buf_set_lines(M.split.bufnr, 0, -1, false, { line .. string.rep(' ', width), '' })
  vim.api.nvim_buf_set_extmark(M.split.bufnr, vim.api.nvim_create_namespace 'db.nvim', 0, 0, {
    end_line = 1,
    hl_group = 'WildMenu',
  })

  local start_col = 0
  local end_col = menu.schema:len()
  if M.active_tab == 'history' then
    start_col = end_col
    end_col = end_col + menu.history:len()
  end

  vim.api.nvim_buf_set_extmark(M.split.bufnr, vim.api.nvim_create_namespace 'db.nvim', 0, start_col, {
    end_col = end_col,
    hl_group = 'TabLineSel',
  })
end

M.render_history = function(connId)
  local history_file = utils.get_history_path(connId)

  local file, err = io.open(history_file, 'r')

  if not file then
    vim.notify('Unable to read : ' .. err)
    return
  end

  for line in file:lines() do
    local item = vim.json.decode(line)
    table.insert(M.histories, item)
    M.push(item)
  end
end

M.render_schema = function(connId)
  local db = require 'db'
  local conn = db.active_connections[connId]

  local tbl_nodes = vim.tbl_map(function(tbl_name)
    return NuiTree.Node { name = tbl_name, type = 'table' }
  end, conn.tables or {})

  local node = NuiTree.Node({ name = conn.name, type = 'connection' }, tbl_nodes)
  node:expand()

  local tree = NuiTree {
    winid = M.split.winid,
    bufnr = M.split.bufnr,
    nodes = { node },
    prepare_node = function(n)
      local line = NuiLine()
      if n.type == 'connection' then
        line:append('󱘖 ', 'SpecialChar')
      end
      if n.type == 'table' then
        line:append ' ├─ '
        line:append('󰓱 ', 'SpecialChar')
      end
      line:append(n.name)
      return line
    end,
  }

  tree:render(M.starting_index + 1)

  M.split:map('n', '<CR>', function()
    if M.active_tab ~= 'schema' then
      return
    end

    local n = tree:get_node()
    if not n then
      return
    end

    if n:is_expanded() then
      n:collapse()
    else
      if n:expand() then
        tree:render()
      end
    end

    if n.type == 'table' then
      db.select_table(n.name)
    end
  end)

  M.split:map('n', 'i', function()
    local n = tree:get_node()
    if not n then
      return
    end
    db.show_table_information(n.name)
  end)
end

M.add = function(connId, query)
  local history = {
    datetime = require('os').date '%d/%m %H:%M',
    query = query,
  }
  local history_file = utils.get_history_path(connId)
  vim.system({ 'tee', '-a', history_file }, { stdin = vim.json.encode(history) .. '\n' })
  table.insert(M.histories, history)

  if M.active_tab ~= 'history' then
    return
  end

  M.unlock_buffer()
  M.push(history)
  M.lock_buffer()
end

M.push = function(item)
  if not M.is_valid() then
    return
  end
  local ns = vim.api.nvim_create_namespace 'db'
  local lines = {}
  for s in item.query:gmatch '[^\r\n]+' do
    table.insert(lines, s)
  end
  vim.api.nvim_buf_set_lines(M.split.bufnr, M.starting_index, M.starting_index, true, lines)
  vim.api.nvim_buf_set_extmark(M.split.bufnr, ns, M.starting_index, 0, {
    end_row = M.starting_index + #lines,
    virt_text_pos = 'right_align',
    virt_text = {
      { ' ' .. item.datetime, 'LineNr' },
    },
  })
end

M.is_valid = function()
  if not M.split or not M.split.winid or not vim.api.nvim_win_is_valid(M.split.winid) or not vim.api.nvim_buf_is_valid(M.split.bufnr) then
    return false
  end

  return true
end

M.unlock_buffer = function()
  if M.is_valid() then
    vim.api.nvim_set_option_value('modifiable', true, { buf = M.split.bufnr })
    vim.api.nvim_set_option_value('readonly', false, { buf = M.split.bufnr })
  end
end

M.lock_buffer = function()
  if M.is_valid() then
    vim.api.nvim_set_option_value('modifiable', false, { buf = M.split.bufnr })
    vim.api.nvim_set_option_value('readonly', true, { buf = M.split.bufnr })
    local filetype = 'mysql'
    if M.active_tab == 'schema' then
      filetype = 'text'
    end
    vim.api.nvim_set_option_value('filetype', filetype, { buf = M.split.bufnr })
  end
end

return M
