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
    ambient_chance = 4,
    min_tail_length = 5,
    tail_length_ratio = 0.4,
    extra_streams = -1,
    trail_depth = 1,
  },
  dense = {
    ambient_chance = 14,
    min_tail_length = 8,
    tail_length_ratio = 0.65,
    extra_streams = -1,
    trail_depth = 2,
  },
}

local defaults = vim.tbl_extend('force', {
  density = 'balanced',
  charset = 'movie',
  min_delay = 1,
  max_delay = 6,
  tick_ms = 25,
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

return M
