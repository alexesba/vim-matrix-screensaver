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
  assert(cfg.ambient_chance == 5)
  assert(cfg.auto_start == false)
  assert(cfg.idle_seconds == 300)
end)

test('setup merges opts into vim.g.matrix', function()
  vim.g.matrix = nil
  require('matrix').setup({ auto_start = true, idle_seconds = 90 })
  local cfg = require('matrix.config').get()
  assert(cfg.auto_start == true)
  assert(cfg.idle_seconds == 90)
  vim.g.matrix = nil
  require('matrix.idle').teardown()
end)

test('idle timeout converts seconds to milliseconds', function()
  vim.g.matrix = { idle_seconds = 120 }
  assert(require('matrix.idle')._test_idle_ms() == 120000)
  vim.g.matrix = nil
end)

test('ambient flicker clears each frame', function()
  screensaver._test_ambient_decay()
end)

test('adaptive tick stretches interval on large screens', function()
  vim.g.matrix = { tick_ms = 33, adaptive_tick = true }
  local small = screensaver._test_effective_tick_ms(80, 24)
  local medium = screensaver._test_effective_tick_ms(160, 50)
  local large = screensaver._test_effective_tick_ms(240, 80)
  assert(small == 33, 'small screen should use base tick_ms')
  assert(medium == 50, 'medium screen should use at least 50ms')
  assert(large == 66, 'large screen should use at least 66ms')
  vim.g.matrix = nil
end)

test('ambient attempts scale with columns not area', function()
  local column_scaled, area_scaled = screensaver._test_ambient_attempts(200, 60, 5)
  assert(column_scaled == 10, 'expected 10 column-scaled attempts, got ' .. column_scaled)
  assert(area_scaled == 600, 'area baseline should still be 600')
  assert(column_scaled < area_scaled, 'column scaling should reduce large-screen work')
end)

test('katakana probe skips when no UI is attached', function()
  if #vim.api.nvim_list_uis() == 0 then
    assert(require('matrix.charset').katakana_renders() == true)
  end
end)

test('movie_lite charset avoids katakana for ASCII-only fonts', function()
  local chars = require('matrix.charset').get('movie_lite')
  assert(#chars > 0, 'movie_lite charset should not be empty')
  local glyph_set = table.concat(chars)
  assert(glyph_set:find('0', 1, true), 'movie_lite should include digits')
  assert(not glyph_set:find('ｱ', 1, true), 'movie_lite should omit katakana')
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

test(':Matrix defaults to movie charset', function()
  local ok, name = screensaver._test_parse_args({})
  assert(ok, 'bare :Matrix args should parse')
  assert(name == 'movie', 'default charset should be movie')
end)

test('Matrix rejects invalid arguments', function()
  screensaver.start({ 'not', 'numbers' })
  assert(not screensaver.running(), 'screensaver should not run with invalid args')
end)

test(':Matrix starts and fills the screen', function()
  vim.cmd('Matrix')

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
