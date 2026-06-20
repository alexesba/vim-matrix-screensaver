local M = {}

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

local function chars_from_range(first, last)
  local chars = {}
  for code = first, last do
    table.insert(chars, vim.fn.nr2char(code))
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

  -- Halfwidth katakana: the glyph set used in the film's digital rain.
  vim.list_extend(chars, chars_from_range(0xFF66, 0xFF9F))

  -- Arabic numerals and Latin letters.
  vim.list_extend(chars, chars_from_range(48, 57))
  vim.list_extend(chars, chars_from_range(65, 90))
  vim.list_extend(chars, chars_from_range(97, 122))

  -- Turned-letter lookalikes that suggest reversed Roman characters.
  vim.list_extend(chars, chars_from_string('∀ԁԃԄԆԇӘɐɑɔəɟɥʎʌ'))

  -- Decorative symbols, including Taurus (bull motif from Revolutions).
  vim.list_extend(chars, chars_from_string('±×÷·°¢£¥§¶†‡•♉♊♈'))

  return filter_single_width(chars)
end

function M.get(name)
  if name == 'classic' then
    return M.classic()
  end
  return M.movie()
end

return M
