local M = {}

M.get_data_path = function(path)
  path = path or ''
  local folder = vim.fn.stdpath 'data' .. '/mysql/'

  if not (vim.loop or vim.uv).fs_stat(folder) then
    vim.fn.system { 'mkdir', folder }
  end

  return folder .. path
end

M.slug = function(text)
  return string.gsub(text:lower(), '%s+', '-')
end

M.get_history_path = function(connId)
  return M.get_data_path(M.slug(connId) .. '.history')
end

return M
