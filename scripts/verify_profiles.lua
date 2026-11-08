local seal = "rex-agent/sealed-v1"
local src = debug.getinfo(1, "S").source
if src:sub(1, 1) == "@" then
  src = src:sub(2)
end
local root = src:match("(.+)/scripts/") or src:match("^(.*)scripts/")
if not root or root == "" then
  root = "."
elseif root:sub(-1) == "/" then
  root = root:sub(1, -2)
end
local loader = assert(loadfile(root .. "/lua/rex_agent/profiles.lua"))
local profiles = loader(seal)

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: got %q want %q", msg, a, b))
  end
end

local plan, err = profiles.build({})
assert(plan, err)
assert_eq(plan.catalog.profiles[1].agent.label, "nvim-agent", "default label")
assert_eq(plan.catalog.profiles[1].name, "nvim-agent", "legacy name is label")

local d = profiles.resolve(plan.catalog, nil)
assert(d.tag == "chosen", "single profile chosen")

plan = profiles.build({
  profiles = {
    { name = "a", argv = { "pi" }, label = "la" },
    { name = "b", argv = { "claude" }, label = "lb" },
  },
})
d = profiles.resolve(plan.catalog, nil)
assert(d.tag == "choose", "multi without default chooses")

plan = profiles.build({
  default = "b",
  profiles = {
    { name = "a", argv = { "pi" }, label = "la" },
    { name = "b", argv = { "claude" }, label = "lb" },
  },
})
d = profiles.resolve(plan.catalog, nil)
assert(d.tag == "chosen", "default chosen")
assert_eq(d.agent.label, "lb", "default agent label")

local plan_mix, err_mix = profiles.build({
  agent = { "pi" },
  profiles = { { name = "x", argv = { "y" }, label = "z" } },
})
assert(plan_mix == nil and err_mix and err_mix:find("not both"), "reject profiles + agent")

local plan_dup, err_dup = profiles.build({
  profiles = {
    { name = "a", argv = { "pi" }, label = "same" },
    { name = "b", argv = { "claude" }, label = "same" },
  },
})
assert(plan_dup == nil and err_dup and err_dup:find("duplicate label"), "duplicate label rejected")

print("verify_profiles: ok")
