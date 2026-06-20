local M = {}

local defaults = {
  charset = 'movie',
  min_delay = 1,
  max_delay = 6,
  tick_ms = 25,
  ambient_chance = 0,
}

function M.get()
  local user = vim.g.matrix
  if type(user) ~= 'table' then
    user = {}
  end
  return vim.tbl_deep_extend('force', vim.deepcopy(defaults), user)
end

return M
