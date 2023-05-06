# utf8.nvim

The missing utf8 module for Neovim Lua.

The license for this library is CC0.
Feel free to embed and use it.

It does not depend on Neovim, so it will work in environments where Luajit bit library are available.

# Why?

Neovim Lua runtime is Luajit (equivalent to Lua 5.1), so it does not have some of the libraries that recent Lua has.

# What is this?

This library provides basic support for UTF-8 encoding.
It does not provide any support for Unicode other than the handling of the encoding.

(Citing the [official reference manual](http://www.lua.org/manual/5.4/manual.html#6.5))

# Functions

Functions are roughly equivalent to those of the above reference manual, except that `require()` is required.

```lua
local utf8 = require("utf8")
```

Check [doc](./doc/utf8.txt) for details.
