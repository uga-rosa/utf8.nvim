local utf8 = require("utf8")

---Expect the error to occur
---@param errmsg string
---@param func function
---@param ... unknown
local function check_error(errmsg, func, ...)
  local s, err = pcall(func, ...)
  assert.is_false(s)
  assert.is_truthy(err:find(errmsg))
end

describe("utf8", function()
  describe("char()", function()
    it("normal", function()
      assert.equals("", utf8.char())
      assert.equals("\0abc\1", utf8.char(0, 97, 98, 99, 1))
    end)

    it("undo with codepoint", function()
      assert.equals(0x0, utf8.codepoint(utf8.char(0x0)))
      assert.equals(0x10FFFF, utf8.codepoint(utf8.char(0x10FFFF)))
    end)

    it("error (invalid integers)", function()
      check_error("value out of range", utf8.char, -1)
      check_error("value out of range", utf8.char, 0x10FFFF + 1)
    end)
  end)

  describe("codes()", function()
    it("single byte characters", function()
      local s = "hello"
      local expects = {
        { 1, "h" },
        { 2, "e" },
        { 3, "l" },
        { 4, "l" },
        { 5, "o" },
      }
      local f = utf8.codes(s)
      for i = 1, 5 do
        assert.same(expects[i], { f() })
      end
    end)

    it("multi byte characters", function()
      local s = "こんにちは"
      local expects = {
        { 1, "こ" },
        { 4, "ん" },
        { 7, "に" },
        { 10, "ち" },
        { 13, "は" },
      }
      local f = utf8.codes(s)
      for i = 1, 5 do
        assert.same(expects[i], { f() })
      end
    end)

    it("error (invalid byte sequence)", function()
      local function errorcodes(s)
        check_error("invalid UTF%-8 code", function()
          for c in utf8.codes(s) do
            assert(c)
          end
        end)
      end
      errorcodes("ab\xff")
      errorcodes("in\x80valid")
      errorcodes("\xbfinvalid")
      errorcodes("αλφ\xBFα")
    end)
  end)

  describe("codepoint", function()
    it("normal", function()
      assert.equals(0xD800 - 1, utf8.codepoint("\u{D7FF}"))
      assert.equals(0xDFFF + 1, utf8.codepoint("\u{E000}"))
      assert.equals(0xD800 - 1, utf8.codepoint("\u{D7FF}", 1, 1))
      assert.equals(0xDFFF + 1, utf8.codepoint("\u{E000}", 1, 1))
    end)

    it("error (invalid byte sequence)", function()
      local s = "áéí\128"
      check_error("invalid UTF%-8 code", utf8.codepoint, s, 1, #s)
      check_error("out of bounds", utf8.codepoint, s, 1, #s + 1)
    end)
  end)

  describe("len()", function()
    it("normal", function()
      assert.equals(1, utf8.len("a"))
      assert.equals(4, utf8.len("abcd"))
      assert.equals(1, utf8.len("あ"))
      assert.equals(3, utf8.len("あいう"))
    end)

    it("error (invalid byte sequence)", function()
      ---@param s string
      ---@param init_invalid_byte integer
      local function check(s, init_invalid_byte)
        local a, b = utf8.len(s)
        assert.is_nil(a)
        assert.equals(init_invalid_byte, b)
      end
      check("abc\xE3def", 4)
      check("\xF4\x9F\xBF", 1)
      check("\xF4\x9F\xBF\xBF", 1)
      -- spurious continuation bytes
      check("汉字\x80", #"汉字" + 1)
      check("\x80hello", 1)
      check("hel\x80lo", 4)
      check("汉字\xBF", #"汉字" + 1)
      check("\xBFhello", 1)
      check("hel\xBFlo", 4)
    end)

    it("error (invalid indexes)", function()
      check_error("out of bounds", utf8.len, "abc", 0, 2)
      check_error("out of bounds", utf8.len, "abc", 1, 4)
    end)

    it("error (invalid utf8 code)", function()
      local function invalid(s)
        check_error("invalid UTF%-8 code", utf8.codepoint, s)
        assert.is_nil(utf8.len(s))
      end
      -- UTF-8 representation for 0x11ffff (value out of valid range)
      invalid("\xF4\x9F\xBF\xBF")

      -- overlong sequence
      invalid("\xC0\x80") -- zero
      invalid("\xC1\xBF") -- 0x7F (should be coded in 1 byte)
      invalid("\xE0\x9F\xBF") -- 0x7FF (should be coded in 2 bytes)
      invalid("\xF0\x8F\xBF\xBF") -- 0xFFFF (should be coded in 3 bytes)

      -- invalid bytes
      invalid("\x80") -- continuation byte
      invalid("\xBF") -- continuation byte
      invalid("\xFE") -- invalid byte
      invalid("\xFF") -- invalid byte
    end)
  end)

  describe("offset()", function()
    describe("normal", function()
      it("positive n", function()
        local s = "日本語a-4\0éó"
        local i = 0
        local pre_p
        for p, _ in utf8.codes(s) do
          i = i + 1
          assert.equals(p, utf8.offset(s, i))
          assert.equals(p, utf8.offset(s, 1, p))
          if pre_p then
            assert.equals(p, utf8.offset(s, 2, pre_p))
          end
          pre_p = p
        end
      end)

      it("negative n", function()
        local s = "日本語a-4\0éó"
        local i = 0
        local pre_p
        for p, _ in utf8.codes(s) do
          i = i + 1
          local n_from_end = i - utf8.len(s) - 1
          assert.equals(p, utf8.offset(s, n_from_end))
          if pre_p then
            assert.equals(pre_p, utf8.offset(s, -1, p))
          end
          pre_p = p
        end
      end)

      it("zero n", function()
        local s = "日本語a-4\0éó"
        local ps = { 1, 1, 1, 4, 4, 4, 7, 7, 7, 10, 11, 12, 13, 14, 14, 16, 16 }
        for i, p in ipairs(ps) do
          assert.equals(p, utf8.offset(s, 0, i))
        end
      end)
    end)

    it("out of bounds (return nil)", function()
      assert.is_nil(utf8.offset("alo", 5))
      assert.is_nil(utf8.offset("alo", -4))
    end)

    it("error in initial position for offset", function()
      check_error("position out of bounds", utf8.offset, "abc", 1, 5)
      check_error("position out of bounds", utf8.offset, "abc", 1, -4)
      check_error("position out of bounds", utf8.offset, "", 1, 2)
      check_error("position out of bounds", utf8.offset, "", 1, -1)
      check_error("continuation byte", utf8.offset, "𦧺", 1, 2)
      check_error("continuation byte", utf8.offset, "𦧺", 1, 2)
      check_error("continuation byte", utf8.offset, "\x80", 1)
    end)
  end)
end)
