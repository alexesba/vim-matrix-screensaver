local M = {}

-- Film glyph research:
-- https://scifi.stackexchange.com/questions/137575/
-- The Matrix rain uses mirrored halfwidth katakana, Arabic digits (no 6),
-- punctuation, the letter Z, and kanji such as 日. Terminals cannot mirror
-- glyphs, so we use the documented Unicode characters directly.

local MOVIE_KATAKANA = 'ｦｱｳｴｵｶｷｹｺｻｼｽｾｿﾀﾂﾃﾅﾆﾇﾈﾊﾋﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜｰｼﾅﾓﾘｹﾒｴｷﾑｾｽﾀﾍ'
local MOVIE_KATAKANA_EXTRA = 'ｲｸﾁﾄﾉﾌﾔﾖﾙﾚﾛﾝｧｨｩｪｫｬｭｮｯ'
local MOVIE_DIGITS = '012345789' -- digit 6 does not appear in the film rain
local MOVIE_LATIN = 'Z'
local MOVIE_PUNCTUATION = ':."=*+-<>¦|_?'
local MOVIE_KANJI = '日'

local KATAKANA_PROBE_SAMPLES = { 'ｱ', 'ｦ', 'ﾊ' }
local REPLACEMENT_CHAR = 0xFFFD

local function is_single_width(char)
  return vim.fn.strdisplaywidth(char, 0) == 1
end

local function filter_single_width(chars)
  local out = {}
  local seen = {}
  for _, char in ipairs(chars) do
    if not seen[char] and is_single_width(char) then
      seen[char] = true
      table.insert(out, char)
    end
  end
  return out
end

local function chars_from_string(str)
  local chars = {}
  local idx = 0
  while true do
    local char = vim.fn.strcharpart(str, idx, 1)
    if char == '' then
      break
    end
    table.insert(chars, char)
    idx = idx + 1
  end
  return chars
end

function M.classic()
  local chars = {}
  for code = 33, 126 do
    if code ~= 95 and code ~= 96 then
      table.insert(chars, vim.fn.nr2char(code))
    end
  end
  return chars
end

function M.movie()
  local chars = {}
  vim.list_extend(chars, chars_from_string(MOVIE_KATAKANA))
  vim.list_extend(chars, chars_from_string(MOVIE_KATAKANA_EXTRA))
  vim.list_extend(chars, chars_from_string(MOVIE_DIGITS))
  vim.list_extend(chars, chars_from_string(MOVIE_LATIN))
  vim.list_extend(chars, chars_from_string(MOVIE_PUNCTUATION))
  vim.list_extend(chars, chars_from_string(MOVIE_KANJI))
  return filter_single_width(chars)
end

-- Film numerals, Z, and symbols only. Use when the terminal font lacks
-- halfwidth katakana (U+FF66–U+FF9F) and would show □ tofu boxes instead.
function M.movie_lite()
  local chars = {}
  vim.list_extend(chars, chars_from_string(MOVIE_DIGITS))
  vim.list_extend(chars, chars_from_string(MOVIE_LATIN))
  vim.list_extend(chars, chars_from_string(MOVIE_PUNCTUATION))
  return filter_single_width(chars)
end

local function screen_pos_for_win(win)
  if vim.fn.has('nvim-0.11') == 1 then
    local pos = vim.fn.win_screenpos(win)
    if type(pos) == 'table' and pos.row and pos.col then
      return pos.row + 1, pos.col + 1
    end
  end
  local col, row = vim.fn.winscreenpos(win)
  if col and row and col > 0 and row > 0 then
    return row, col
  end
  return nil, nil
end

--- Best-effort check: render sample katakana and read screenchar().
--- Returns true when glyphs appear to render, or when probing is unavailable.
function M.katakana_renders()
  if #vim.api.nvim_list_uis() == 0 then
    return true
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local win
  local function cleanup()
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  local ok, renders = pcall(function()
    vim.bo[buf].modifiable = true
    vim.bo[buf].fileencoding = 'utf-8'

    for _, char in ipairs(KATAKANA_PROBE_SAMPLES) do
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { char })
      local width = math.max(1, vim.fn.strdisplaywidth(char, 0))
      if not win or not vim.api.nvim_win_is_valid(win) then
        win = vim.api.nvim_open_win(buf, false, {
          relative = 'editor',
          width = width,
          height = 1,
          row = 0,
          col = 0,
          style = 'minimal',
          border = 'none',
          noautocmd = true,
          focusable = false,
          zindex = 300,
        })
      else
        vim.api.nvim_win_set_width(win, width)
      end

      vim.cmd('redraw!')
      local screen_row, screen_col = screen_pos_for_win(win)
      if not screen_row then
        return true
      end

      local expected = vim.fn.char2nr(char)
      local shown = vim.fn.screenchar(screen_row, screen_col)
      if shown == 0 or shown == REPLACEMENT_CHAR or shown ~= expected then
        return false
      end
    end
    return true
  end)

  cleanup()

  if not ok then
    return true
  end
  return renders
end

function M.get(name)
  if name == 'classic' then
    return M.classic()
  end
  if name == 'movie_lite' then
    return M.movie_lite()
  end
  return M.movie()
end

return M
