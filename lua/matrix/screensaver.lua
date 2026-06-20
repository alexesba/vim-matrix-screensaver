local charset = require('matrix.charset')
local config = require('matrix.config')

local M = {}

local session_file = vim.fn.tempname()
local SEED_MOD = 2147483647

local settings = config.get()

local mindelay
local maxdelay
local tick_ms
local ambient_chance
local min_tail_length
local tail_length_ratio
local extra_streams
local trail_depth
local default_charset

local function apply_settings(cfg)
  cfg = cfg or config.get()
  mindelay = cfg.min_delay
  maxdelay = cfg.max_delay
  tick_ms = cfg.tick_ms
  ambient_chance = cfg.ambient_chance
  min_tail_length = cfg.min_tail_length
  tail_length_ratio = cfg.tail_length_ratio
  extra_streams = cfg.extra_streams
  trail_depth = cfg.trail_depth
  default_charset = cfg.charset
end

apply_settings(settings)

local state = {}

local function rand()
  state.seed = (state.seed * 22695477 + 1) % SEED_MOD
  return state.seed
end

local function random_char()
  return state.chars[rand() % state.char_count + 1]
end

local function mark_dirty(row)
  if state.dirty_rows then
    state.dirty_rows[row] = true
  end
end

local function mark_all_dirty()
  state.dirty_rows = {}
  for row = 1, state.height do
    state.dirty_rows[row] = true
  end
end

local function tail_length()
  if tail_length_ratio >= 1.0 then
    return rand() % state.height + min_tail_length
  end
  local span = math.max(1, math.floor(state.height * tail_length_ratio))
  return rand() % span + min_tail_length
end

local function create_object(obj, min_reserve)
  min_reserve = min_reserve or 4
  local x = nil
  for threshold = min_reserve, 1, -1 do
    for _ = 1, state.columns * 4 do
      local candidate = rand() % state.columns
      if state.reserve[candidate] > threshold then
        x = candidate
        break
      end
    end
    if x ~= nil then
      break
    end
  end
  if x == nil then
    return false
  end
  obj.x = x
  obj.y = 1
  obj.t = rand() % state.speeds[obj.x]
  obj.head = rand() % 4
  obj.len = tail_length()
  state.reserve[obj.x] = 1 - obj.len
  return true
end

local function set_cell(row, col, char, hl)
  if row < 1 or row > state.height or col < 1 or col > state.width then
    return
  end
  state.grid[row][col] = char
  state.hls[row][col] = hl
  if state.ambient then
    state.ambient[row][col] = false
  end
  mark_dirty(row)
end

local function decay_ambient()
  if not state.ambient_cells or ambient_chance <= 0 then
    return
  end
  for i = #state.ambient_cells, 1, -1 do
    local cell = state.ambient_cells[i]
    local row, col = cell.row, cell.col
    state.grid[row][col] = ' '
    state.hls[row][col] = 'hidden'
    state.ambient[row][col] = false
    mark_dirty(row)
    table.remove(state.ambient_cells, i)
  end
end

local function add_ambient_chars()
  local attempts = math.floor(state.width * state.height * ambient_chance / 100)
  if attempts <= 0 then
    return
  end
  for _ = 1, attempts do
    local row = rand() % state.height + 1
    local col = rand() % state.width + 1
    if state.hls[row][col] == 'hidden' then
      state.grid[row][col] = random_char()
      state.hls[row][col] = 'dim'
      state.ambient[row][col] = true
      table.insert(state.ambient_cells, { row = row, col = col })
      mark_dirty(row)
    end
  end
end

local function draw_object(obj)
  local x = obj.x + 1
  local y = obj.y

  if y <= state.height then
    if obj.head ~= 0 then
      set_cell(y, x, random_char(), 'head')
      for offset = 1, trail_depth do
        if y > offset then
          local hl = offset == 1 and 'bright' or 'normal'
          set_cell(y - offset, x, random_char(), hl)
        end
      end
    else
      set_cell(y, x, random_char(), rand() % 2 == 0 and 'bright' or 'normal')
    end
  end

  local tail_y = y - obj.len
  if tail_y >= 1 and tail_y <= state.height then
    set_cell(tail_y, x, ' ', 'hidden')
  end
  state.reserve[obj.x] = tail_y
end

local hl_groups = {
  hidden = 'MatrixHidden',
  dim = 'MatrixDim',
  normal = 'MatrixNormal',
  bright = 'MatrixBold',
  head = 'MatrixHead',
}

local function clear_row_marks()
  if not state.row_marks or not state.buf then
    state.row_marks = {}
    state.next_mark_id = 1
    return
  end
  for _, marks in pairs(state.row_marks) do
    for _, id in ipairs(marks) do
      pcall(vim.api.nvim_buf_del_extmark, state.buf, state.ns, id)
    end
  end
  state.row_marks = {}
  state.next_mark_id = 1
end

local function build_row(row)
  local grid_row = state.grid[row]
  local offsets = {}
  local parts = {}
  local byte_pos = 0
  for col = 1, state.width do
    offsets[col] = byte_pos
    local char = grid_row[col]
    parts[col] = char
    byte_pos = byte_pos + #char
  end
  offsets[state.width + 1] = byte_pos
  return table.concat(parts), offsets
end

local function hl_runs(row, offsets)
  local runs = {}
  local col = 1
  while col <= state.width do
    local hl = state.hls[row][col]
    local hl_start = col
    while col <= state.width and state.hls[row][col] == hl do
      col = col + 1
    end
    runs[#runs + 1] = {
      start_col = offsets[hl_start],
      end_col = offsets[col],
      hl_group = hl_groups[hl],
    }
  end
  return runs
end

local function render_row(row)
  local line, offsets = build_row(row)
  vim.api.nvim_buf_set_lines(state.buf, row - 1, row, false, { line })

  local runs = hl_runs(row, offsets)
  local prev_marks = state.row_marks[row] or {}
  local marks = {}

  for i, run in ipairs(runs) do
    local id = prev_marks[i]
    if not id then
      id = state.next_mark_id
      state.next_mark_id = state.next_mark_id + 1
    end
    marks[i] = id
    vim.api.nvim_buf_set_extmark(state.buf, state.ns, row - 1, run.start_col, {
      id = id,
      end_row = row - 1,
      end_col = run.end_col,
      hl_group = run.hl_group,
      strict = false,
    })
  end

  for i = #runs + 1, #prev_marks do
    pcall(vim.api.nvim_buf_del_extmark, state.buf, state.ns, prev_marks[i])
  end

  state.row_marks[row] = marks
end

local function render_frame(full)
  if full then
    mark_all_dirty()
  end

  if not state.dirty_rows or not next(state.dirty_rows) then
    return
  end

  for row = 1, state.height do
    if state.dirty_rows[row] then
      render_row(row)
    end
  end
  state.dirty_rows = {}
end

local function animate()
  decay_ambient()

  for _, obj in ipairs(state.objects) do
    if obj.t <= 0 then
      if obj.y - obj.len <= state.height then
        draw_object(obj)
        obj.t = state.speeds[obj.x]
        obj.y = obj.y + 1
      else
        if not create_object(obj) then
          obj.t = rand() % 4 + 1
        end
      end
    end
    obj.t = obj.t - 1
  end

  if ambient_chance > 0 then
    add_ambient_chars()
  end
  render_frame()
end

local focus_group = nil

local function remove_focus_handler()
  if focus_group then
    pcall(vim.api.nvim_clear_autocmds, { group = focus_group })
    focus_group = nil
  end
end

local function install_focus_handler()
  remove_focus_handler()
  focus_group = vim.api.nvim_create_augroup('MatrixFocus', { clear = true })
  vim.api.nvim_create_autocmd({ 'FocusGained', 'VimResume' }, {
    group = focus_group,
    callback = function()
      if not state.run then
        return
      end
      vim.schedule(function()
        if state.run then
          animate()
          pcall(vim.cmd, 'redraw')
        end
      end)
    end,
  })
end

local function init_grid()
  state.grid = {}
  state.hls = {}
  state.ambient = {}
  for row = 1, state.height do
    state.grid[row] = {}
    state.hls[row] = {}
    state.ambient[row] = {}
    for col = 1, state.width do
      state.grid[row][col] = ' '
      state.hls[row][col] = 'hidden'
      state.ambient[row][col] = false
    end
  end
end

local function window_width()
  return vim.api.nvim_win_get_width(state.win)
end

local function reset()
  state.width = window_width()
  state.height = vim.api.nvim_win_get_height(state.win)

  if state.width < 10 or state.height < 8 then
    state.run = false
    return
  end

  state.columns = state.width
  state.speeds = {}
  state.reserve = {}

  for i = 0, state.columns - 1 do
    state.speeds[i] = rand() % (maxdelay - mindelay) + mindelay
    state.reserve[i] = state.height
  end

  init_grid()
  clear_row_marks()
  state.ambient_cells = {}
  mark_all_dirty()

  state.objects = {}
  local obj_count = math.max(0, state.columns - 2)
  for _ = 1, obj_count do
    local obj = {}
    if create_object(obj) then
      obj.y = rand() % state.height + 1
      table.insert(state.objects, obj)
    end
  end

  local extras = extra_streams
  if extras < 0 then
    extras = math.max(2, math.floor(state.columns / 8))
  end
  for _ = 1, extras do
    local obj = {}
    if create_object(obj, 2) then
      obj.y = rand() % state.height + 1
      table.insert(state.objects, obj)
    end
  end

  render_frame()
end

local function define_highlights()
  local highlights = {
    MatrixHidden = { fg = '#000000', bg = '#000000', ctermfg = 'Black', ctermbg = 'Black' },
    MatrixDim = { fg = '#004400', bg = '#000000', ctermfg = 'Black', ctermbg = 'Black' },
    MatrixNormal = { fg = '#008000', bg = '#000000', ctermfg = 'DarkGreen', ctermbg = 'Black' },
    MatrixBold = { fg = '#00ff00', bg = '#000000', ctermfg = 'LightGreen', ctermbg = 'Black' },
    MatrixHead = { fg = '#ffffff', bg = '#000000', ctermfg = 'White', ctermbg = 'Black' },
  }

  for name, attrs in pairs(highlights) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

local saved = {}

local function save_option(name, value)
  saved[name] = value
end

local function hide_cursor()
  save_option('gcr', vim.o.gcr)

  vim.api.nvim_set_hl(0, 'MatrixCursor', {
    blend = 100,
    fg = '#000000',
    bg = '#000000',
    ctermfg = 'Black',
    ctermbg = 'Black',
  })
  vim.api.nvim_set_hl(0, 'Cursor', { link = 'MatrixCursor', default = true })
  vim.api.nvim_set_hl(0, 'lCursor', { link = 'MatrixCursor', default = true })
  vim.o.guicursor = 'a:Ver1-blinkon0-MatrixCursor,i:Ver1-blinkon0-MatrixCursor'
  pcall(vim.cmd, 'redrawcursor')
end

local function restore_cursor()
  if saved.gcr ~= nil then
    vim.o.gcr = saved.gcr
    saved.gcr = nil
  end
  pcall(vim.cmd, 'hi clear MatrixCursor')
  pcall(vim.cmd, 'hi clear Cursor')
  pcall(vim.cmd, 'hi clear lCursor')
end

local function init()
  vim.cmd('mksession! ' .. vim.fn.fnameescape(session_file))
  saved.num_orig_win = vim.fn.winnr('$')

  vim.cmd('1wincmd w')
  vim.cmd('silent! new')

  if vim.fn.winnr('$') ~= saved.num_orig_win + 1 then
    return false
  end

  saved.newbuf = vim.api.nvim_get_current_buf()
  vim.cmd('only')

  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_get_current_buf()
  state.ns = vim.api.nvim_create_namespace('matrix')
  state.row_marks = {}
  state.next_mark_id = 1

  vim.bo.buftype = 'nofile'
  vim.bo.bufhidden = 'delete'
  vim.bo.modifiable = true
  vim.bo.swapfile = false
  vim.bo.textwidth = 0

  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.wrap = false
  vim.wo.signcolumn = 'no'
  vim.wo.foldcolumn = '0'
  vim.wo.colorcolumn = ''
  vim.wo.cursorline = false
  vim.wo.cursorcolumn = false
  vim.wo.spell = false
  vim.wo.sidescrolloff = 0
  vim.wo.scrolloff = 0
  vim.wo.winbar = ''

  save_option('winhighlight', vim.wo.winhighlight)
  vim.wo.winhighlight = table.concat({
    'Normal:MatrixHidden',
    'NormalNC:MatrixHidden',
    'SignColumn:MatrixHidden',
    'EndOfBuffer:MatrixHidden',
    'FoldColumn:MatrixHidden',
    'WinSeparator:MatrixHidden',
    'CursorLine:MatrixHidden',
    'CursorColumn:MatrixHidden',
    'Whitespace:MatrixHidden',
  }, ',')

  save_option('ch', vim.o.ch)
  save_option('ls', vim.o.ls)
  save_option('lz', vim.o.lz)
  save_option('sm', vim.o.sm)
  save_option('smd', vim.o.smd)
  save_option('siso', vim.o.siso)
  save_option('so', vim.o.so)
  save_option('ve', vim.o.ve)
  save_option('ei', vim.o.ei)
  save_option('ru', vim.o.ru)
  save_option('sc', vim.o.sc)

  vim.o.ch = 0
  vim.o.ls = 0
  vim.o.lz = true
  vim.o.sm = false
  vim.o.smd = false
  vim.o.siso = 0
  vim.o.so = 0
  vim.o.ve = 'all'
  vim.o.ei = 'all'
  vim.o.ru = false
  vim.o.sc = false

  hide_cursor()

  if vim.fn.has('gui_running') == 1 then
    save_option('go', vim.o.go)
    vim.o.go = ''
  end

  if vim.fn.has('title') == 1 then
    save_option('titlestring', vim.o.titlestring)
    vim.o.titlestring = ' '
  end

  state.seed = vim.fn.localtime() % SEED_MOD
  state.run = true

  define_highlights()
  reset()
  install_focus_handler()
  return true
end

local function drain_typeahead()
  local expr = vim.fn.has('nvim-0.10') == 1 and { noblock = true } or 1
  for _ = 1, 256 do
    local ok, c = pcall(vim.fn.getchar, expr)
    if not ok or c == 0 then
      break
    end
  end
end

local function install_exit_keys(shutdown_fn, is_shutting_down)
  local opts = { buffer = state.buf, silent = true, nowait = true }
  for _, key in ipairs({ '<LeftMouse>', '<RightMouse>' }) do
    pcall(vim.keymap.set, 'n', key, shutdown_fn, opts)
  end

  if type(vim.on_key) == 'function' then
    state.key_ns = vim.api.nvim_create_namespace('matrix_keys')
    vim.on_key(function(_key)
      if is_shutting_down() then
        return ''
      end
      if not state.run then
        return _key
      end
      vim.schedule(shutdown_fn)
      return ''
    end, state.key_ns)
    return
  end

  for c = 32, 126 do
    pcall(vim.keymap.set, 'n', vim.fn.nr2char(c), shutdown_fn, opts)
  end
  for _, key in ipairs({
    '<Esc>',
    '<CR>',
    '<Space>',
    '<Tab>',
    '<BS>',
    '<Del>',
    '<Up>',
    '<Down>',
    '<Left>',
    '<Right>',
  }) do
    pcall(vim.keymap.set, 'n', key, shutdown_fn, opts)
  end
end

local function remove_exit_keys()
  if state.key_ns then
    pcall(vim.on_key, nil, state.key_ns)
    state.key_ns = nil
  end
end

local function cleanup()
  remove_exit_keys()
  remove_focus_handler()
  pcall(restore_cursor)

  if saved.go ~= nil then
    vim.o.go = saved.go
  end
  if saved.ru ~= nil then
    vim.o.ru = saved.ru
    vim.o.sc = saved.sc
  end
  if saved.titlestring ~= nil then
    vim.o.titlestring = saved.titlestring
  end

  vim.o.ch = saved.ch
  vim.o.ls = saved.ls
  vim.o.lz = saved.lz
  vim.o.sm = saved.sm
  vim.o.smd = saved.smd
  vim.o.siso = saved.siso
  vim.o.so = saved.so
  vim.o.ve = saved.ve
  vim.o.ei = saved.ei

  if saved.winhighlight ~= nil then
    vim.wo.winhighlight = saved.winhighlight
  end

  vim.cmd('source ' .. vim.fn.fnameescape(session_file))
  if saved.newbuf and vim.api.nvim_buf_is_valid(saved.newbuf) then
    vim.cmd('bwipe! ' .. saved.newbuf)
  end

  pcall(drain_typeahead)
  saved = {}

  pcall(function()
    require('matrix.idle').resume()
  end)
end

local CHARSETS = { classic = true, movie = true }

local function parse_args(args)
  apply_settings(config.get())

  local selected_charset = default_charset or 'movie'
  local delay_args = {}
  local idx = 1

  if args[idx] and CHARSETS[args[idx]] then
    selected_charset = args[idx]
    idx = idx + 1
  end

  for i = idx, #args do
    table.insert(delay_args, args[i])
  end

  if #delay_args == 2 then
    local values = { tonumber(delay_args[1]), tonumber(delay_args[2]) }
    table.sort(values)
    if values[1] and values[2] and values[1] > 0 and values[2] > values[1] then
      mindelay = values[1]
      maxdelay = values[2]
      return true, selected_charset
    end
    return false, selected_charset
  end

  if #delay_args > 0 then
    return false, selected_charset
  end

  return true, selected_charset
end

function M.start(args)
  if vim.fn.has('nvim') ~= 1 then
    vim.api.nvim_echo({ { 'Matrix screensaver requires Neovim', 'ErrorMsg' } }, true, {})
    return
  end

  apply_settings(config.get())

  local ok, selected_charset = parse_args(args)
  if not ok then
    vim.api.nvim_echo({
      {
        'ERROR! Usage: :Matrix [classic|movie] [mindelay maxdelay]',
        'ErrorMsg',
      },
    }, true, {})
    return
  end

  state.chars = charset.get(selected_charset)
  state.char_count = #state.chars

  if state.char_count == 0 then
    vim.api.nvim_echo({
      {
        'ERROR! No displayable characters for charset: ' .. selected_charset,
        'ErrorMsg',
      },
    }, true, {})
    return
  end

  if not init() then
    vim.api.nvim_echo({ { 'Can not create window', 'ErrorMsg' } }, true, {})
    return
  end

  pcall(function()
    require('matrix.idle').pause()
  end)

  local timer = vim.loop.new_timer()
  local shutdown_started = false

  local function shutdown()
    if shutdown_started then
      return
    end
    shutdown_started = true
    state.run = false
    pcall(function()
      timer:stop()
      timer:close()
    end)
    cleanup()
  end

  install_exit_keys(shutdown, function()
    return shutdown_started
  end)

  local function on_tick()
    if not state.run then
      shutdown()
      return
    end

    local width = window_width()
    local height = vim.api.nvim_win_get_height(state.win)
    if width ~= state.width or height ~= state.height then
      reset()
    else
      animate()
    end
  end

  timer:start(0, tick_ms, vim.schedule_wrap(on_tick))
end

function M.stop()
  state.run = false
end

function M.running()
  return state.run == true
end

---@private Used by tests/matrix_spec.lua
function M._test_prng(iterations)
  state.seed = vim.fn.localtime() % SEED_MOD
  for _ = 1, iterations do
    local n = rand()
    assert(n == n, 'rand() produced NaN')
    assert(n >= 0 and n < SEED_MOD, 'rand() out of range: ' .. tostring(n))
    local col = n % 80
    assert(col >= 0 and col < 80, 'column index out of range: ' .. tostring(col))
  end
end

---@private Used by tests/matrix_spec.lua
function M._test_parse_args(args)
  return parse_args(args)
end

---@private Used by tests/matrix_spec.lua
function M._test_charset(name)
  local chars = charset.get(name)
  assert(#chars > 0, 'charset is empty: ' .. name)
  for _, char in ipairs(chars) do
    assert(vim.fn.strdisplaywidth(char, 0) == 1, 'double-width char in charset: ' .. char)
  end
  if name == 'movie' then
    local has_katakana = false
    for _, char in ipairs(chars) do
      local code = vim.fn.char2nr(char)
      if code >= 0xFF66 and code <= 0xFF9F then
        has_katakana = true
        break
      end
    end
    assert(has_katakana, 'movie charset should include halfwidth katakana')
  end
  return chars
end

---@private Used by tests/matrix_spec.lua
function M._test_ambient_decay()
  apply_settings(config.get())
  state.height = 2
  state.width = 2
  state.grid = {
    { 'a', 'b' },
    { 'c', 'd' },
  }
  state.hls = {
    { 'normal', 'dim' },
    { 'dim', 'normal' },
  }
  state.ambient = {
    { false, true },
    { true, false },
  }
  state.ambient_cells = {
    { row = 1, col = 2 },
    { row = 2, col = 1 },
  }

  decay_ambient()

  assert(state.grid[1][2] == ' ', 'ambient cell should clear')
  assert(state.hls[1][2] == 'hidden', 'ambient cell should hide')
  assert(not state.ambient[1][2], 'ambient flag should reset')
  assert(state.grid[2][1] == ' ', 'ambient cell should clear')
  assert(state.grid[1][1] == 'a', 'stream cell should remain')
  assert(state.grid[2][2] == 'd', 'stream cell should remain')
end

return M
