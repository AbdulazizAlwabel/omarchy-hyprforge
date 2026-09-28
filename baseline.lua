-- Reads Hyprland Lua config files by running them against recording stubs and
-- prints the curves and animations they declare as JSON. Nothing is applied.
--
--   lua baseline.lua <file> [<file> ...]
--
-- Later files override earlier ones leaf by leaf, the same way Hyprland does,
-- so passing Omarchy's default looknfeel.lua and then the user's gives the
-- animation set Hyprforge scales and edits.

local curves, curveOrder = {}, {}
local anims, animOrder = {}, {}

local function noop() end
local stub = setmetatable({}, { __index = function() return noop end })

hl = setmetatable({
  curve = function(name, spec)
    if type(name) ~= "string" or type(spec) ~= "table" then return end
    if not curves[name] then curveOrder[#curveOrder + 1] = name end
    curves[name] = spec
  end,
  animation = function(spec)
    if type(spec) ~= "table" or type(spec.leaf) ~= "string" then return end
    if not anims[spec.leaf] then animOrder[#animOrder + 1] = spec.leaf end
    anims[spec.leaf] = spec
  end,
}, { __index = function() return noop end })
o = stub

local function esc(s)
  return (tostring(s):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end))
end

local function num(v)
  local n = tonumber(v)
  if not n or n ~= n then return "null" end
  return string.format("%.4f", n):gsub("%.?0+$", "")
end

for i = 1, #arg do
  local chunk = loadfile(arg[i], "t")
  if chunk then pcall(chunk) end
end

local out = {}
local cs = {}
for _, name in ipairs(curveOrder) do
  local c = curves[name]
  if c.type == "spring" then
    cs[#cs + 1] = string.format('{"name":"%s","type":"spring","mass":%s,"stiffness":%s,"dampening":%s}',
      esc(name), num(c.mass or 1), num(c.stiffness or 100), num(c.dampening or c.damping or 10))
  else
    local p = c.points or { { 0, 0 }, { 1, 1 } }
    cs[#cs + 1] = string.format('{"name":"%s","type":"bezier","points":[%s,%s,%s,%s]}',
      esc(name), num(p[1][1]), num(p[1][2]), num(p[2][1]), num(p[2][2]))
  end
end

local as = {}
for _, leaf in ipairs(animOrder) do
  local a = anims[leaf]
  local enabled = not (a.enabled == false or a.enabled == 0)
  local curve = a.bezier or a.spring or a.curve or ""
  as[#as + 1] = string.format('{"leaf":"%s","enabled":%s,"speed":%s,"curve":"%s","style":"%s"}',
    esc(leaf), tostring(enabled), a.speed and num(a.speed) or "null", esc(curve), esc(a.style or ""))
end

print('{"curves":[' .. table.concat(cs, ",") .. '],"animations":[' .. table.concat(as, ",") .. ']}')
