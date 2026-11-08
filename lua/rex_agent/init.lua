local M = {}

local SEAL = "rex-agent/sealed-v1"

local program = nil
local rex = nil
local context = nil

local keys_sealed = false

local function private_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("(.*)/[^/]+$") or "."
end

---@param name string
---@param deps? unknown
local function private(name, deps)
  local path = private_dir() .. "/" .. name .. ".lua"
  local loader, err = loadfile(path)
  if not loader then
    error(err)
  end
  return loader(SEAL, deps)
end

local profiles = private("profiles")

local default_plan = profiles.build({})
---@type Catalog
local catalog = default_plan.catalog

local function run_pipeline(facts)
  local step = program.transition(facts, nil)
  if step.tag == "probe" then
    local sight = rex.probe(step)
    step = program.transition(facts, sight)
  end
  if step.tag == "probe" then
    vim.notify("rex_agent: pane probe did not resolve", vim.log.levels.ERROR)
    return
  end
  if step.tag == "refuse" then
    vim.notify(step.reason, vim.log.levels.WARN)
    return
  end
  local result = rex.enact(step)
  if result.tag == "failed" then
    vim.notify(result.message, vim.log.levels.ERROR)
  end
end

---@alias Pane "floating"|"right"

---@class ProfileSpec
---@field name string
---@field argv string[]
---@field label string
---@field keys? string

---@class SetupOpts
---@field profiles? ProfileSpec[]
---@field default? string
---@field keys? string|false
---@field agent? string|string[]
---@field label? string
---@field pane? Pane

---@param opts? SetupOpts
function M.setup(opts)
  local plan, err = profiles.build(opts)
  if not plan then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  catalog = plan.catalog

  if keys_sealed then
    return
  end

  if profiles.bind(plan, function(which)
    M.ask(which)
  end) then
    keys_sealed = true
  end
end

---@param which? string
function M.ask(which)
  local decision = profiles.resolve(catalog, which)
  if decision.tag == "reject" then
    vim.notify(decision.reason, vim.log.levels.ERROR)
    return
  end

  local capture = context.capture()
  if capture.tag == "blocked" then
    run_pipeline(context.assemble(capture))
    return
  end

  local function finish(agent)
    run_pipeline(context.assemble(capture, agent))
  end

  if decision.tag == "chosen" then
    finish(decision.agent)
    return
  end

  profiles.present(catalog, finish)
end

local mention = private("mention")
context = private("context", mention)
program = private("program")
rex = private("rex", mention)

return M
