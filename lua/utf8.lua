local utf8 = {}

local bit = require("bit") -- luajit

local band = bit.band
local bor = bit.bor
local rshift = bit.rshift
local lshift = bit.lshift

---The pattern (a string, not a function) "[\0-\x7F\xC2-\xF4][\x80-\xBF]*",
---which matches exactly one UTF-8 byte sequence, assuming that the subject is a valid UTF-8 string.
utf8.charpattern = "[%z\x01-\x7F\xC2-\xF4][\x80-\xBF]*"

---@param idx integer
---@param func_name string
---@param range_name string
---@return string @error message
local function create_errmsg(idx, func_name, range_name)
  return string.format("bad argument #%s to '%s' (%s out of range)", idx, func_name, range_name)
end

---Converts indexes of a string to positive numbers.
---@param str string
---@param idx integer
---@param msg string
---@return integer
local function validate_range(str, idx, msg)
  idx = idx > 0 and idx or #str + idx + 1
  if idx < 0 or idx > #str then
    error(msg, 2)
  end
  return idx
end

---Receives zero or more integers, converts each one to its corresponding UTF-8 byte sequence
---and returns a string with the concatenation of all these sequences.
---@vararg integer
---@return string
function utf8.char(...)
  local buffer = {}
  for i, v in ipairs({ ... }) do
    if v < 0 or v > 0x10FFFF then
      error(create_errmsg(i, "char", "value"), 2)
    elseif v < 0x80 then
      -- single-byte
      buffer[i] = string.char(v)
    elseif v < 0x800 then
      -- two-byte
      local b1 = bor(0xC0, band(rshift(v, 6), 0x1F)) -- 110x-xxxx
      local b2 = bor(0x80, band(v, 0x3F)) -- 10xx-xxxx
      buffer[i] = string.char(b1, b2)
    elseif v < 0x10000 then
      -- three-byte
      local b1 = bor(0xE0, band(rshift(v, 12), 0x0F)) -- 1110-xxxx
      local b2 = bor(0x80, band(rshift(v, 6), 0x3F)) -- 10xx-xxxx
      local b3 = bor(0x80, band(v, 0x3F)) -- 10xx-xxxx
      buffer[i] = string.char(b1, b2, b3)
    else
      -- four-byte
      local b1 = bor(0xF0, band(rshift(v, 18), 0x07)) -- 1111-0xxx
      local b2 = bor(0x80, band(rshift(v, 12), 0x3F)) -- 10xx-xxxx
      local b3 = bor(0x80, band(rshift(v, 6), 0x3F)) -- 10xx-xxxx
      local b4 = bor(0x80, band(v, 0x3F)) -- 10xx-xxxx
      buffer[i] = string.char(b1, b2, b3, b4)
    end
  end
  return table.concat(buffer, "")
end

---@param b number bit
---@return boolean
local function is_tail(b)
  -- 10xx-xxxx (0x80-BF)
  return band(b, 0xC0) == 0x80
end

---Returns the next one character range.
---References: https://datatracker.ietf.org/doc/html/rfc3629#section-4
---@param s string
---@param start_pos integer
---@return integer? start_pos, integer? end_pos
local function next_char(s, start_pos)
  local b1 = s:byte(start_pos)
  if not b1 then
    return -- for offset's #s+1
  end
  local b2 = s:byte(start_pos + 1) or -1
  local b3 = s:byte(start_pos + 2) or -1
  local b4 = s:byte(start_pos + 3) or -1

  -- single byte
  if b1 <= 0x7F then
    return start_pos, start_pos
  -- two byte
  elseif 0xC2 <= b1 and b1 <= 0xDF then
    local end_pos = start_pos + 1
    if is_tail(b2) then
      return start_pos, end_pos
    end
  -- three byte
  elseif 0xE0 <= b1 and b1 <= 0xEF then
    local end_pos = start_pos + 2
    if b1 == 0xE0 then
      if (0xA0 <= b2 and b2 <= 0xBF) and is_tail(b3) then
        return start_pos, end_pos
      end
    elseif b1 == 0xED then
      if (0x80 <= b2 and b2 <= 0x9F) and is_tail(b3) then
        return start_pos, end_pos
      end
    else
      if is_tail(b2) and is_tail(b3) then
        return start_pos, end_pos
      end
    end
  -- four byte
  elseif 0xF0 <= b1 and b1 <= 0xF4 then
    local end_pos = start_pos + 3
    if b1 == 0xF0 then
      if (0x90 <= b2 and b2 <= 0xBF) and is_tail(b3) and is_tail(b4) then
        return start_pos, end_pos
      end
    elseif b1 == 0xF4 then
      if (0x80 <= b2 and b2 <= 0x8F) and is_tail(b3) and is_tail(b4) then
        return start_pos, end_pos
      end
    else
      if is_tail(b2) and is_tail(b3) and is_tail(b4) then
        return start_pos, end_pos
      end
    end
  end
end

---Returns values so that the construction
---
---for p, c in utf8.codes(s) do body end
---
---will iterate over all UTF-8 characters in string s, with p being the position (in bytes) and c the code point of each character.
---It raises an error if it meets any invalid byte sequence.
---@param s string
---@return function iterator
function utf8.codes(s)
  vim.validate({
    s = { s, "string" },
  })

  local i = 1
  return function()
    if i > #s then
      return
    end

    local start_pos, end_pos = next_char(s, i)
    if start_pos == nil then
      error("invalid UTF-8 code", 2)
    end

    i = end_pos + 1
    return start_pos, s:sub(start_pos, end_pos)
  end
end

---Returns the code points (as integers) from all characters in s that start between byte position i and j (both included).
---The default for i is 1 and for j is i.
---It raises an error if it meets any invalid byte sequence.
---@param s string
---@param i? integer start position. default=1
---@param j? integer end position. default=i
---@return integer @code point
function utf8.codepoint(s, i, j)
  vim.validate({
    s = { s, "string" },
    i = { i, "number", true },
    j = { j, "number", true },
  })
  i = validate_range(s, i or 1, create_errmsg(2, "codepoint", "initial position"))
  j = validate_range(s, j or i, create_errmsg(3, "codepoint", "final position"))

  local ret = {}
  repeat
    local char_start, char_end = next_char(s, i)
    if char_start == nil then
      error("invalid UTF-8 code", 2)
    end

    i = char_end + 1

    local len = char_end - char_start + 1
    if len == 1 then
      -- single-byte
      table.insert(ret, s:byte(char_start))
    else
      -- multi-byte
      local b1 = s:byte(char_start)
      b1 = band(lshift(b1, len + 1), 0xFF) -- e.g. 110x-xxxx -> xxxx-x000
      b1 = lshift(b1, len * 5 - 7) -- >> len+1 and << (len-1)*6

      local cp = 0
      for k = char_start + 1, char_end do
        local bn = s:byte(k)
        cp = bor(lshift(cp, 6), band(bn, 0x3F))
      end

      cp = bor(b1, cp)
      table.insert(ret, cp)
    end
  until char_end >= j

  return unpack(ret)
end

---Returns the number of UTF-8 characters in string s that start between positions i and j (both inclusive).
---The default for i is 1 and for j is -1.
---If it finds any invalid byte sequence, returns fail plus the position of the first invalid byte.
---@param s string
---@param i? integer start position. default=1
---@param j? integer end position. default=-1
---@return integer | nil
---@return integer?
function utf8.len(s, i, j)
  vim.validate({
    s = { s, "string" },
    i = { i, "number", true },
    j = { j, "number", true },
  })
  i = validate_range(s, i or 1, create_errmsg(2, "len", "initial position"))
  j = validate_range(s, j or -1, create_errmsg(3, "len", "final position"))

  local len = 0

  repeat
    local char_start, char_end = next_char(s, i)
    if char_start == nil then
      return nil, i
    end

    i = char_end + 1
    len = len + 1
  until char_end >= j

  return len
end

---Returns the position (in bytes) where the encoding of the n-th character of s (counting from position i) starts.
---A negative n gets characters before position i.
---The default for i is 1 when n is non-negative and #s+1 otherwise, so that utf8.offset(s, -n) gets the offset of the n-th character from the end of the string.
---If the specified character is neither in the subject nor right after its end, the function returns fail.
---
---As a special case, when n is 0 the function returns the start of the encoding of the character that contains the i-th byte of s.
---@param s string
---@param n integer
---@param i? integer start position. if n >= 0, default=1, otherwise default=#s+1
---@return integer?
function utf8.offset(s, n, i)
  vim.validate({
    s = { s, "string" },
    n = { n, "number" },
    i = { i, "number", true },
  })

  i = i or n >= 0 and 1 or #s + 1

  if n >= 0 or i ~= #s + 1 then
    i = validate_range(s, i, create_errmsg(3, "offset", "position"))
  end

  if n == 0 then
    for j = i, 1, -1 do
      local char_start = next_char(s, j)
      if char_start then
        return char_start
      end
    end
  elseif n > 0 then
    if not next_char(s, i) then
      error("initial position is a continuation byte", 2)
    end

    for j = i, #s do
      local char_start = next_char(s, j)
      if char_start then
        n = n - 1
        if n == 0 then
          return char_start
        end
      end
    end
  else
    if i ~= #s + 1 and not next_char(s, i) then
      error("initial position is a continuation byte", 2)
    end

    for j = i, 1, -1 do
      local char_start = next_char(s, j)
      if char_start then
        n = n + 1
        if n == 0 then
          return char_start
        end
      end
    end
  end
end

return utf8
