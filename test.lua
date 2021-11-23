local u
local ok, _utf8 = pcall(require, "utf8")
if ok then
    u = _utf8
else
    u = utf8
end

local len = u.len()
