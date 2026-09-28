-- Runs a generated hyprforge.lua against recording stubs.
--   k <path> <type> <value>   hl.config leaf
--   c <name> <type>           hl.curve
--   a <leaf> <enabled>        hl.animation
--   w <name> <match>          hl.window_rule
--   s <workspace>             hl.workspace_rule
--   l <name>                  hl.layer_rule
local out = {}
local function emit(...) out[#out + 1] = table.concat({ ... }, "\t") end

local function walk(t, prefix)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local v = t[k]
    local p = prefix == "" and tostring(k) or (prefix .. ":" .. tostring(k))
    if type(v) == "table" then
      if v.top ~= nil then emit("k", p, "table", v.top) else walk(v, p) end
    else
      emit("k", p, type(v), tostring(v))
    end
  end
end

hl = {
  config = function(t) walk(t, "") end,
  curve = function(name, spec) emit("c", name, spec.type) end,
  animation = function(t) emit("a", t.leaf, tostring(t.enabled)) end,
  window_rule = function(t) emit("w", t.name or "", t.match and (t.match.class or t.match.tag or t.match.workspace) or "") end,
  workspace_rule = function(t) emit("s", t.workspace) end,
  layer_rule = function(t) emit("l", t.name or "") end,
  get_config = function() return 0 end,
}
local realOpen = io.open
io.open = function(p, mode)
  if mode == "w" then return nil end
  return realOpen(p, mode)
end

local chunk = assert(loadfile(arg[1]))
chunk()
print(table.concat(out, "\n"))
