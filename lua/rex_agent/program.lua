local seal = ...
if seal ~= "rex-agent/sealed-v1" then
  error("rex_agent.program is internal; call require('rex_agent').ask()", 2)
end

local M = {}

local TRANSITION_FLOATING = {
  ["blocked:none"] = "refuse",
  ["ready:none"] = "probe",
  ["ready:failed"] = "refuse",
  ["ready:absent"] = "open",
  ["ready:tiled"] = "raise",
  ["ready:floating"] = "reuse",
}

local TRANSITION_RIGHT = {
  ["blocked:none"] = "refuse",
  ["ready:none"] = "probe",
  ["ready:failed"] = "refuse",
  ["ready:absent"] = "open",
  ["ready:tiled"] = "reuse",
  ["ready:floating"] = "reuse",
}

---@param pane Pane|nil
---@return table<string, string>
local function transitions_for(pane)
  if pane == "right" then
    return TRANSITION_RIGHT
  end
  return TRANSITION_FLOATING
end

---@param facts AskFacts
---@param sight PaneSight|nil
---@return RefuseProgram
local function build_refuse(facts, sight)
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
local function build_probe(facts, _sight)
  return {
    tag = "probe",
    binding = facts.binding,
    label = facts.config.label,
  }
end

---@param facts AskFacts
---@param sight PaneSight
---@return OpenProgram
local function build_open(facts, sight)
  local program = {
    tag = "open",
    binding = facts.binding,
    label = facts.config.label,
    cwd = facts.cwd,
    argv = facts.config.argv,
    seed = facts.seed,
    window_id = sight.window_id,
  }
  if facts.config.pane == "right" then
    program.open_via = "split"
    program.split = {
      direction = "horizontal",
      side = "after",
      anchor_id = facts.binding.anchor,
    }
  else
    program.open_via = "float"
  end
  return program
end

---@param facts AskFacts
---@param sight PaneSight
---@return RaiseProgram
local function build_raise(facts, sight)
  return {
    tag = "raise",
    binding = facts.binding,
    label = facts.config.label,
    block_id = sight.block_id,
    seed = facts.seed,
  }
end

---@param facts AskFacts
---@return ReuseProgram
local function build_reuse(facts, _sight)
  return {
    tag = "reuse",
    binding = facts.binding,
    label = facts.config.label,
    seed = facts.seed,
  }
end

local BUILD = {
  refuse = build_refuse,
  probe = build_probe,
  open = build_open,
  raise = build_raise,
  reuse = build_reuse,
}

---@param facts AskFacts
---@param sight PaneSight|nil
---@return PaneProgram
function M.transition(facts, sight)
  local key = facts.tag .. ":" .. (sight and sight.tag or "none")
  local action = transitions_for(facts.config.pane)[key]
  if not action then
    error("unknown pane transition: " .. key)
  end
  return BUILD[action](facts, sight)
end

return M
