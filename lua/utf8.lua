local utf8 = {}

local bit = require("bit") -- luajit

local band = bit.band
local bor = bit.bor
local rshift = bit.rshift
local lshift = bit.lshift

---Same as official
---The pattern, which matches exactly one UTF-8 byte sequence, assuming that the subject is a valid UTF-8 string.
utf8.charpattern = "[%z\x01-\x7F\xC2-\xFD][\x80-\xBF]*"

---@param idx integer
---@param func_name string
---@param range_name string
local function create_errmsg(idx, func_name, range_name)
    return string.format("bad argument #%s to '%s' (%s out of range)", idx, func_name, range_name)
end

---Converts indexes of a string to positive numbers.
---@param str string
---@param idx integer
---@return boolean, integer
local function validate_range(str, idx)
    idx = idx > 0 and idx or #str + idx + 1
    if idx < 0 or idx > #str then
        return false
    end
    return true, idx
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

---Returns the next one character range.
---@param str string
---@param start_pos number
---@return number start_pos, number end_pos
local function next_char(str, start_pos)
    local end_pos

    local b1 = str:byte(start_pos)
    if b1 <= 0x7F then
        -- single-byte
        return start_pos, start_pos
    elseif b1 >= 0xC2 and b1 <= 0xDF then
        -- two-byte
        end_pos = start_pos + 1
    elseif b1 >= 0xE0 and b1 <= 0xEF then
        -- three-byte
        end_pos = start_pos + 2
    elseif b1 >= 0xF0 and b1 <= 0xF4 then
        -- four-byte
        end_pos = start_pos + 3
    else
        -- non first byte of multi-byte
        return
    end

    -- validate (end_pos)
    if end_pos > #str then
        return
    end
    -- validate (continuation)
    for _, bn in ipairs({ str:byte(start_pos + 1, end_pos) }) do
        if band(bn, 0xC0) ~= 0x80 then -- 10xx-xxxx?
            return
        end
    end

    return start_pos, end_pos
end

---Iterates over all UTF-8 characters in string str.
---@param str string
---@return function iterator
function utf8.codes(str)
    vim.validate({
        str = { str, "string" },
    })

    local i = 1
    return function()
        if i > #str then
            return
        end

        local start_pos, end_pos = next_char(str, i)
        if start_pos == nil then
            error("invalid UTF-8 code", 2)
        end

        i = end_pos + 1
        return start_pos, str:sub(start_pos, end_pos)
    end
end

---Returns the code points (as integers) from all characters in str
---that start between byte position start_pos and end_pos (both inclusive).
---@param str string
---@param start_pos? integer #default=1
---@param end_pos? integer #default=start_pos
---@return integer #code point
function utf8.codepoint(str, start_pos, end_pos)
    vim.validate({
        str = { str, "string" },
        start_pos = { start_pos, "number", true },
        end_pos = { end_pos, "number", true },
    })

    local ok
    ok, start_pos = validate_range(str, start_pos or 1)
    if not ok then
        error(create_errmsg(2, "codepoint", "initial potision"), 2)
    end
    ok, end_pos = validate_range(str, end_pos or start_pos)
    if not ok then
        error(create_errmsg(3, "codepoint", "final potision"), 2)
    end

    local ret = {}
    repeat
        local char_start, char_end = next_char(str, start_pos)
        if char_start == nil then
            error("invalid UTF-8 code", 2)
        end

        start_pos = char_end + 1

        local len = char_end - char_start + 1
        if len == 1 then
            -- single-byte
            table.insert(ret, str:byte(char_start))
        else
            -- multi-byte
            local b1 = str:byte(char_start)
            b1 = band(lshift(b1, len + 1), 0xFF) -- e.g. 110x-xxxx -> xxxx-x000
            b1 = lshift(b1, len * 5 - 7) -- >> len+1 and << (len-1)*6

            local cp = 0
            for i = char_start + 1, char_end do
                local bn = str:byte(i)
                cp = bor(lshift(cp, 6), band(bn, 0x3F))
            end

            cp = bor(b1, cp)
            table.insert(ret, cp)
        end

    until char_end >= end_pos

    return unpack(ret)
end

---Returns the number of UTF-8 characters in string str
---that start between start_pos and end_pos (both inclusive).
---If it finds any invalid byte sequence, returns false and the position of the first invalid byte.
---@param str string
---@param start_pos? integer #default=1
---@param end_pos? integer #default=-1
---@return integer #Or false, integer
function utf8.len(str, start_pos, end_pos)
    vim.validate({
        str = { str, "string" },
        start_pos = { start_pos, "number", true },
        end_pos = { end_pos, "number", true },
    })

    local ok
    ok, start_pos = validate_range(str, start_pos or 1)
    if not ok then
        error(create_errmsg(2, "len", "initial potision"), 2)
    end
    ok, end_pos = validate_range(str, end_pos or -1)
    if not ok then
        error(create_errmsg(3, "len", "final potision"), 2)
    end

    local len = 0

    repeat
        local char_start, char_end = next_char(str, start_pos)
        if char_start == nil then
            return false, start_pos
        end

        start_pos = char_end + 1
        len = len + 1
    until char_end >= end_pos

    return len
end

---Returns the position (in bytes) where the encoding of the n-th character of s (counting from position start_pos) starts.
---A negative n gets characters before position start_pos. utf8.offset(s, -n) gets the offset of the n-th character from the end of the string.
---If the specified character is neither in the subject nor right after its end, the function returns fail.
---
---As a special case, when n is 0 the function returns the start of the encoding of the character that contains the start_pos-th byte of str.
---@param str string
---@param n integer
---@param start_pos? integer #if n > 0, default=1, else default=#str
---@return integer #Or false
function utf8.offset(str, n, start_pos)
    vim.validate({
        str = { str, "string" },
        n = { n, "number" },
        start_pos = { start_pos, "number", true },
    })

    local ok
    ok, start_pos = validate_range(str, start_pos or n >= 0 and 1 or #str)
    if not ok then
        error(create_errmsg(3, "offset", "position"), 2)
    end

    if n == 0 then
        for i = start_pos, 1, -1 do
            local char_start = next_char(str, i)
            if char_start then
                return char_start
            end
        end
        return
    end

    if not next_char(str, start_pos) then
        error("initial position is a continuation byte", 2)
    end

    local find_start, find_end, find_step
    if n > 0 then
        find_start = start_pos
        find_end = #str
        find_step = 1
    else
        n = -n
        find_start = start_pos
        find_end = 1
        find_step = -1
    end

    for i = find_start, find_end, find_step do
        local char_start = next_char(str, i)
        if char_start then
            n = n - 1
            if n == 0 then
                return char_start
            end
        end
    end
end

return utf8
