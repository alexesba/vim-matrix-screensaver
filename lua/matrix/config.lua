local M = {}

local presets = {
  sparse = {
    ambient_chance = 0,
    min_tail_length = 3,
    tail_length_ratio = 1.0,
    extra_streams = 0,
    trail_depth = 1,
  },
  balanced = {
    ambient_chance = 5,
    min_tail_length = 6,
    tail_length_ratio = 1.0,
    extra_streams = -1,
    trail_depth = 2,
  },
  dense = {
    ambient_chance = 14,
    min_tail_length = 8,
    tail_length_ratio = 1.0,
    extra_streams = -1,
    trail_depth = 2,
  },
}

local defaults = vim.tbl_extend('force', {
  density = 'balanced',
  charset = 'movie',
  -- When true, use movie_lite (ASCII film symbols) if charset is "movie".
  -- Avoids □ boxes when the terminal font lacks halfwidth katakana.
  font_safe = false,
  -- When true, notify once per session if movie katakana fail to render on screen.
  font_warning = true,
  min_delay = 1,
  max_delay = 6,
  tick_ms = 33,
  auto_start = false,
  idle_seconds = 300,
}, presets.balanced)

function M.get()
  local user = vim.g.matrix
  if type(user) ~= 'table' then
    user = {}
  end

  local cfg = vim.tbl_deep_extend('force', vim.deepcopy(defaults), user)
  local preset = presets[cfg.density]
  if preset then
    cfg = vim.tbl_deep_extend('force', vim.deepcopy(preset), cfg)
  end
  return cfg
end

---@param opts table|nil User settings from setup() or vim.g.matrix
function M.apply(opts)
  if type(opts) ~= 'table' or vim.tbl_isempty(opts) then
    return
  end
  vim.g.matrix = vim.tbl_deep_extend('force', vim.g.matrix or {}, opts)
end

return M
