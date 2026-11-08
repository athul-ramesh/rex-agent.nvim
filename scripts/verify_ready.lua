--[[
  Headless checks for ready.lua pure helpers.

  Open-then-seed race (measured on Rex): immediate rex send after session.new_layer
  returns exit 0 while capture still shows the agent ready prompt without the mention
  token. Success must be judged from capture tail visibility, not send status.
]]

local seal = "rex-agent/sealed-v1"
local src = debug.getinfo(1, "S").source
if src:sub(1, 1) == "@" then
  src = src:sub(2)
end
local root = src:match("(.+)/scripts/") or "."
if root:sub(-1) == "/" then
  root = root:sub(1, -2)
end

local mention_loader = assert(loadfile(root .. "/lua/rex_agent/mention.lua"))
local mention = mention_loader(seal)
local ready_loader = assert(loadfile(root .. "/lua/rex_agent/ready.lua"))
local ready = ready_loader(seal, mention)

local function assert_true(v, msg)
  if not v then
    error(msg)
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: got %q want %q", msg, a, b))
  end
end

local seed = {
  rel = { text = "lua/rex_agent/rex.lua" },
  span = { first = 291, last = 291 },
}
local needle = ready.needle_for_search(seed)
assert_eq(needle, "@lua/rex_agent/rex.lua#L291", "needle trims trailing space")

assert_eq(ready.coarsen("line 12\nline 99\n"), "line #\nline #", "coarsen digits and trailing blank lines")

local scrollback = string.rep("old context\n", 40)
  .. "Ask Devin something…\n"
  .. "composer idle\n"
local assert_not = not ready.seed_visible_in_tail(scrollback, needle, 30)
assert_true(assert_not, "needle absent in tail when only in ancient scrollback")

local with_seed = scrollback .. " prompt: @lua/rex_agent/rex.lua#L291 \n"
assert_true(ready.seed_visible_in_tail(with_seed, needle, 30), "needle found in last non-empty tail lines")

print("verify_ready: ok")
