local Split = require 'nui.split'
local utils = require 'db.utils'

local M = {}

M.histories = {}

M.open = function(connId)
  M.split = Split {
    relative = 'win',
    position = 'left',
    size = '20%',
    enter = false,
  }
  M.split:mount()

  local history_file = utils.get_history_path(connId)

  for _, line in ipairs(vim.fn.readfile(history_file)) do
    table.insert(M.histories, vim.json.decode(line))
  end

  for _, item in ipairs(M.histories) do
    M.push(item)
  end

  vim.api.nvim_set_option_value('filetype', 'mysql', { buf = M.split.bufnr })
  vim.api.nvim_buf_set_name(M.split.bufnr, 'db.history')
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(M.split.winid),
    callback = function()
      M.split = nil
    end,
  })
end

M.add = function(connId, query)
  if string.sub(query:gsub('%s+', ''), -1) ~= ';' then
    query = query .. ';'
  end

  local history = {
    datetime = require('os').date '%d/%m %H:%M',
    query = query,
  }
  local history_file = utils.get_history_path(connId)
  vim.system({ 'tee', '-a', history_file }, { stdin = vim.json.encode(history) .. '\n' })
  table.insert(M.histories, history)
  M.push(history)
end

M.push = function(item)
  if not M.split or not vim.api.nvim_win_is_valid(M.split.winid) or not vim.api.nvim_buf_is_valid(M.split.bufnr) then
    return
  end
  local ns = vim.api.nvim_create_namespace 'db'
  local line = string.gsub(item.query, '\n', ' ')
  vim.api.nvim_buf_set_lines(M.split.bufnr, 0, 0, false, { line })
  vim.api.nvim_buf_set_extmark(M.split.bufnr, ns, 0, 0, {
    virt_text_pos = 'right_align',
    virt_text = {
      { ' ' .. item.datetime, 'LineNr' },
    },
  })
  vim.api.nvim_win_set_cursor(M.split.winid, { 1, 1 })
end

return M
