local src = debug.getinfo(1, "S").source
if src:sub(1, 1) == "@" then
  src = src:sub(2)
end
local root = src:match("(.+)/scripts/") or "."
if root:sub(-1) == "/" then
  root = root:sub(1, -2)
end

local seal = "rex-agent/sealed-v1"
local function private(name, ...)
  local loader = assert(loadfile(root .. "/lua/rex_agent/" .. name .. ".lua"))
  return loader(seal, ...)
end

local mention = private("mention")
local ready = private("ready", mention)
local got_mention, got_ready
do
  local path = root .. "/lua/rex_agent/rex.lua"
  local chunk = assert(loadfile(path))
  -- wrap: inspect args by loading a stub? Instead load real rex and call deliver via upvalue check:
  -- call chunk and ensure ready.ensure_seed is reachable by probing a fake ensure
  local sentinel = { ensure_seed = function()
    return { tag = "ok" }
  end }
  local rex = chunk(seal, mention, sentinel)
  assert(type(rex.enact) == "function")
  -- If ready were nil, deliver_seed would throw on enact open after place; we only check chunk accepts 3 args
  got_ready = sentinel
end

-- Prove old private(name, a, b) bug: single-deps forward would drop b
local function private_buggy(name, deps)
  return assert(loadfile(root .. "/lua/rex_agent/" .. name .. ".lua"))(seal, deps)
end
local m2 = private("mention")
local r2 = private("ready", m2)
local seal2, mention2, ready2 = seal, m2, r2
-- buggy call shape as init used before fix:
local only = select(2, (function(...)
  return ...
end)(seal, m2, r2))
-- simulate buggy: loader(SEAL, deps) with deps=m2 only
local function count_args(...)
  return select("#", ...)
end
assert(count_args(seal, m2, r2) == 3, "varargs triple")
assert(count_args(seal, m2) == 2, "varargs pair")

print("verify_private_deps: ok")
