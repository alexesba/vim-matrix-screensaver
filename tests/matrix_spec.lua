local screensaver = require('matrix.screensaver')

local passed = 0
local failed = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS: ' .. name)
  else
    failed = failed + 1
    print('FAIL: ' .. name)
    print('      ' .. tostring(err))
  end
end

test('matrix.screensaver module loads', function()
  assert(type(screensaver) == 'table')
  assert(type(screensaver.start) == 'function')
  assert(type(screensaver.stop) == 'function')
end)

test(':Matrix user command is registered', function()
  assert(vim.fn.exists(':Matrix') == 2, ':Matrix command is missing')
end)

test('PRNG stays stable after many iterations', function()
  screensaver._test_prng(1000)
end)

test('config provides balanced defaults', function()
  local cfg = require('matrix.config').get()
  assert(cfg.charset == 'movie')
  assert(cfg.density == 'balanced')
  assert(cfg.min_delay == 1)
  assert(cfg.max_delay == 6)
  assert(cfg.ambient_chance == 7)
end)

test('movie charset uses single-width Matrix glyphs', function()
  local chars = screensaver._test_charset('movie')
  local glyph_set = table.concat(chars)
  assert(not glyph_set:find('6', 1, true), 'movie charset should omit digit 6')
  assert(glyph_set:find('ｱ', 1, true), 'movie charset should include katakana')
  assert(glyph_set:find('Z', 1, true), 'movie charset should include Z')
end)

test('classic charset uses printable ASCII', function()
  local chars = screensaver._test_charset('classic')
  assert(chars[1] == '!', 'classic charset should start with ASCII glyphs')
end)

test('Matrix rejects invalid arguments', function()
  screensaver.start({ 'not', 'numbers' })
  assert(not screensaver.running(), 'screensaver should not run with invalid args')
end)

test(':Matrix starts and fills the screen', function()
  vim.cmd('Matrix movie')

  local started = vim.wait(3000, function()
    return screensaver.running()
  end, 50)

  assert(started, 'Matrix did not start within 3 seconds')

  local height = vim.api.nvim_win_get_height(0)
  local line_count = vim.api.nvim_buf_line_count(0)
  assert(line_count >= height, 'buffer should fill the window height')

  local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ''
  assert(#first_line >= 10, 'first line should span the screen width')

  screensaver.stop()

  local stopped = vim.wait(3000, function()
    return not screensaver.running()
  end, 50)

  assert(stopped, 'Matrix did not stop within 3 seconds')
end)

print(string.format('\n%d passed, %d failed', passed, failed))

if failed > 0 then
  vim.cmd('cquit 1')
end
