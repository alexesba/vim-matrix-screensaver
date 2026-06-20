local config = require('matrix.config')

local M = {}

local timer = nil
local key_ns = nil
local augroup = nil
local paused = false

local ACTIVITY_EVENTS = {
  'CursorMoved',
  'CursorMovedI',
  'InsertEnter',
  'InsertLeave',
  'TextChanged',
  'TextChangedI',
  'CmdlineEnter',
  'CmdlineLeave',
  'WinEnter',
  'BufEnter',
  'CompleteDone',
}

local function screensaver()
  return require('matrix.screensaver')
end

local function enabled()
  return config.get().auto_start == true
end

local function idle_ms()
  local seconds = tonumber(config.get().idle_seconds) or 300
  return math.max(1, math.floor(seconds)) * 1000
end

function M.reset()
  if paused or not enabled() or screensaver().running() then
    return
  end

  if timer == nil then
    timer = vim.loop.new_timer()
  end

  timer:stop()
  timer:start(idle_ms(), 0, vim.schedule_wrap(function()
    if paused or not enabled() or screensaver().running() then
      return
    end
    screensaver().start({})
  end))
end

function M.pause()
  paused = true
  if timer then
    timer:stop()
  end
end

function M.resume()
  paused = false
  M.reset()
end

function M.teardown()
  paused = false
  if timer then
    pcall(function()
      timer:stop()
      timer:close()
    end)
    timer = nil
  end
  if key_ns then
    pcall(vim.on_key, nil, key_ns)
    key_ns = nil
  end
  if augroup then
    pcall(vim.api.nvim_clear_autocmds, { group = augroup })
    augroup = nil
  end
end

function M.setup()
  M.teardown()
  if not enabled() then
    return
  end

  augroup = vim.api.nvim_create_augroup('MatrixIdle', { clear = true })
  for _, event in ipairs(ACTIVITY_EVENTS) do
    vim.api.nvim_create_autocmd(event, {
      group = augroup,
      callback = M.reset,
    })
  end

  if type(vim.on_key) == 'function' then
    key_ns = vim.api.nvim_create_namespace('matrix_idle')
    vim.on_key(function()
      if not paused and enabled() and not screensaver().running() then
        vim.schedule(M.reset)
      end
    end, key_ns)
  end

  M.reset()
end

function M.reload()
  M.setup()
end

---@private Used by tests/matrix_spec.lua
function M._test_idle_ms()
  return idle_ms()
end

return M
