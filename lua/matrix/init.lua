local config = require('matrix.config')

local M = {}

---Merge user options and (re)start idle watching.
---Called automatically on load; lazy.nvim passes `opts` here.
---@param opts table|nil
function M.setup(opts)
  config.apply(opts)
  require('matrix.idle').reload()
end

return M
