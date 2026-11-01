local seal = ...
if seal ~= "rex-agent/sealed-v1" then
  error("rex_agent.program is internal; call require('rex_agent').ask()", 2)
end

local M = {}

local TRANSITION = {
  ["blocked:none"] = "refuse",
  ["ready:none"] = "probe",
  ["ready:failed"] = "refuse",
  ["ready:absent"] = "create",
  ["ready:present"] = "reuse",
}

---@param file FileContext
---@return string
local function seed_text(file)
  return "@" .. file.path .. " " .. file.path .. ":" .. file.span.first .. "-" .. file.span.last .. " "
end

---@param facts AskFacts
---@param seed string|nil
---@param sight PaneSight|nil
---@return RefuseProgram
local function build_refuse(facts, _seed, sight)
  local reason
  if facts.tag == "blocked" then
    reason = facts.reason
  else
    reason = sight.message
  end
  return { tag = "refuse", reason = reason }
end

---@param facts AskFacts
---@return ProbeProgram
local function build_probe(facts, _seed, _sight)
  return {
    tag = "probe",
    binding = facts.binding,
    label = facts.config.label,
  }
end

---@param facts AskFacts
---@param seed string
---@return CreateProgram
local function build_create(facts, seed, _sight)
  return {
    tag = "create",
    binding = facts.binding,
    label = facts.config.label,
    cwd = facts.cwd,
    argv = facts.config.argv,
    split = "right",
    focus_on_create = false,
    seed = seed,
  }
end

---@param facts AskFacts
---@param seed string
---@return ReuseProgram
local function build_reuse(facts, seed, _sight)
  return {
    tag = "reuse",
    binding = facts.binding,
    label = facts.config.label,
    seed = seed,
  }
end

local BUILD = {
  refuse = build_refuse,
  probe = build_probe,
  create = build_create,
  reuse = build_reuse,
}

---@param facts AskFacts
---@param sight PaneSight|nil
---@return PaneProgram
function M.transition(facts, sight)
  local key = facts.tag .. ":" .. (sight and sight.tag or "none")
  local action = TRANSITION[key]
  if not action then
    error("unknown pane transition: " .. key)
  end
  local seed = nil
  if action == "create" or action == "reuse" then
    seed = seed_text(facts.file)
  end
  return BUILD[action](facts, seed, sight)
end

return M
