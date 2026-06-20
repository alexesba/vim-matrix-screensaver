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
local MOVIE_PUNCTUATION = ':."=*+-<>¦|_?@#$%&;'
local MOVIE_KANJI = '日'

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
  -- Remaining halfwidth katakana for visual density while staying single-width.
  for code = 0xFF66, 0xFF9F do
    table.insert(chars, vim.fn.nr2char(code))
  end
  return filter_single_width(chars)
end

function M.get(name)
  if name == 'classic' then
    return M.classic()
  end
  return M.movie()
end

return M
