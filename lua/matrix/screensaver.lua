local charset = require('matrix.charset')

local M = {}

local session_file = vim.fn.tempname()
local SEED_MOD = 2147483647

local mindelay = 2
local maxdelay = 8

local state = {}

local function rand()
  state.seed = (state.seed * 22695477 + 1) % SEED_MOD
  return state.seed
end

local function random_char()
  return state.chars[rand() % state.char_count + 1]
end

local AMBIENT_CHANCE = 18 -- percent of empty cells that flicker each frame

local function create_object(obj, min_reserve)
  min_reserve = min_reserve or 2
  for _ = 1, state.columns * 4 do
    local x = rand() % state.columns
    if state.reserve[x] > min_reserve then
      obj.x = x
      break
    end
  end
  if obj.x == nil then
    return
  end
  obj.y = 1
  obj.t = rand() % state.speeds[obj.x]
  obj.head = rand() % 4
  obj.len = rand() % math.max(4, math.floor(state.height * 0.75)) + 4
  state.reserve[obj.x] = obj.y - obj.len
end

local function seed_column(col)
  local obj = {
    x = col,
    y = rand() % state.height + 1,
    t = rand() % state.speeds[col],
    head = rand() % 4,
    len = rand() % math.max(4, math.floor(state.height * 0.75)) + 4,
  }
  state.reserve[col] = obj.y - obj.len
  return obj
end

local function add_ambient_chars()
  for row = 1, state.height do
    for col = 1, state.width do
      if state.hls[row][col] == 'hidden' and rand() % 100 < AMBIENT_CHANCE then
        state.grid[row][col] = random_char()
        state.hls[row][col] = 'normal'
      end
    end
  end
end

local function set_cell(row, col, char, hl)
  if row < 1 or row > state.height or col < 1 or col > state.width then
    return
  end
  state.grid[row][col] = char
  state.hls[row][col] = hl
end

local function draw_object(obj)
  local x = obj.x + 1
  local y = obj.y

  if y <= state.height then
    if obj.head ~= 0 then
      set_cell(y, x, random_char(), 'head')
      if y > 1 then
        set_cell(y - 1, x, random_char(), rand() % 2 == 0 and 'bright' or 'normal')
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
  normal = 'MatrixNormal',
  bright = 'MatrixBold',
  head = 'MatrixHead',
}

local function pad_line(chars)
  local line = table.concat(chars)
  local display_width = vim.fn.strdisplaywidth(line, 0)
  if display_width < state.width then
    line = line .. string.rep(' ', state.width - display_width)
  end
  return line
end

local function render_frame()
  local lines = {}
  for row = 1, state.height do
    local chars = {}
    for col = 1, state.width do
      chars[col] = state.grid[row][col]
    end
    lines[row] = pad_line(chars)
  end

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)

  for row = 1, state.height do
    local col = 1
    while col <= state.width do
      local hl = state.hls[row][col]
      local start = col - 1
      while col <= state.width and state.hls[row][col] == hl do
        col = col + 1
      end
      vim.api.nvim_buf_add_highlight(
        state.buf,
        state.ns,
        hl_groups[hl],
        row - 1,
        start,
        col - 1
      )
    end
  end
end

local function animate()
  for _, obj in ipairs(state.objects) do
    if obj.t <= 0 then
      if obj.y - obj.len <= state.height then
        draw_object(obj)
        obj.t = state.speeds[obj.x]
        obj.y = obj.y + 1
      else
        create_object(obj)
        if obj.x == nil then
          obj.y = state.height + 1
        end
      end
    end
    obj.t = obj.t - 1
  end

  add_ambient_chars()
  render_frame()
end

local function init_grid()
  state.grid = {}
  state.hls = {}
  for row = 1, state.height do
    state.grid[row] = {}
    state.hls[row] = {}
    for col = 1, state.width do
      state.grid[row][col] = ' '
      state.hls[row][col] = 'hidden'
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

  state.objects = {}
  for col = 0, state.columns - 1 do
    table.insert(state.objects, seed_column(col))
  end

  local extra_streams = math.max(4, math.floor(state.columns / 3))
  for _ = 1, extra_streams do
    local obj = {}
    create_object(obj, 1)
    if obj.x ~= nil then
      table.insert(state.objects, obj)
    end
  end

  for _ = 1, 3 do
    add_ambient_chars()
  end

  render_frame()
end

local function define_highlights()
  local highlights = {
    MatrixHidden = { fg = '#000000', bg = '#000000', ctermfg = 'Black', ctermbg = 'Black' },
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
  return true
end

local function drain_typeahead()
  while vim.fn.getchar(1) ~= 0 do
  end
end

local function install_exit_keys(shutdown_fn, is_shutting_down)
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

  local opts = { buffer = state.buf, silent = true, nowait = true }
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

  drain_typeahead()
  saved = {}
end

local CHARSETS = { classic = true, movie = true }

local function parse_args(args)
  local selected_charset = 'movie'
  local delay_args = {}
  local idx = 1

  if args[idx] and CHARSETS[args[idx]] then
    selected_charset = args[idx]
    idx = idx + 1
  end

  for i = idx, #args do
    table.insert(delay_args, args[i])
  end

  if #delay_args == 0 then
    mindelay = 2
    maxdelay = 8
    return true, selected_charset
  end

  if #delay_args == 2 then
    local values = { tonumber(delay_args[1]), tonumber(delay_args[2]) }
    table.sort(values)
    if values[1] and values[2] and values[1] > 0 and values[2] > values[1] then
      mindelay = values[1]
      maxdelay = values[2]
      return true, selected_charset
    end
  end

  return false, selected_charset
end

function M.start(args)
  if vim.fn.has('nvim') ~= 1 then
    vim.api.nvim_echo({ { 'Matrix screensaver requires Neovim', 'ErrorMsg' } }, true, {})
    return
  end

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

  local timer = vim.loop.new_timer()
  local tick_ms = 30
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

return M
