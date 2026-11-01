local seal = ...
if seal ~= "rex-agent/sealed-v1" then
  error("rex_agent.rex is internal; call require('rex_agent').ask()", 2)
end

local M = {}

local SPLIT_RATIO = "35"

---@param argv string[]
---@return { code: integer|nil, stderr: string }
local function run(argv)
  local obj = vim.system(argv, { text = true })
  local result = obj:wait()
  return {
    code = result.code,
    stderr = result.stderr or "",
  }
end

---@param binding RexBinding
---@param label string
---@return string[]
local function argv_focus(binding, label)
  return {
    "rex",
    "--server",
    binding.server,
    "focus",
    "--session",
    binding.session,
    label,
  }
end

---@param program CreateProgram|ReuseProgram
---@return string[]
local function argv_send(program)
  return {
    "rex",
    "--server",
    program.binding.server,
    "send",
    "--session",
    program.binding.session,
    "--block",
    program.label,
    "--",
    program.seed,
  }
end

---@param program CreateProgram
---@return string[]
local function argv_split(program)
  local argv = {
    "rex",
    "--server",
    program.binding.server,
    "split",
    "--session",
    program.binding.session,
    "--block",
    program.binding.anchor,
    "--split",
    program.split,
    "--ratio",
    SPLIT_RATIO,
    "--label",
    program.label,
    "--cwd",
    program.cwd,
    "--focus=false",
    "--",
  }
  for _, arg in ipairs(program.argv) do
    table.insert(argv, arg)
  end
  return argv
end

---@param code integer|nil
---@param stderr string
---@param what string
---@return string
local function fail_message(code, stderr, what)
  local detail = stderr:match("%S") and stderr:gsub("%s+$", "") or ("exit " .. tostring(code))
  return "rex " .. what .. " failed: " .. detail
end

---@param program ProbeProgram
---@return PaneSight
function M.probe(program)
  local result = run(argv_focus(program.binding, program.label))
  if result.code == nil then
    return { tag = "failed", message = fail_message(nil, result.stderr, "focus") }
  end
  if result.code == 0 then
    return { tag = "present" }
  end
  if result.code == 3 then
    return { tag = "absent" }
  end
  return { tag = "failed", message = fail_message(result.code, result.stderr, "focus") }
end

---@param program CreateProgram|ReuseProgram
---@return EnactResult
function M.enact(program)
  if program.tag == "create" then
    local split_result = run(argv_split(program))
    if split_result.code ~= 0 then
      return { tag = "failed", message = fail_message(split_result.code, split_result.stderr, "split") }
    end
  end

  local send_result = run(argv_send(program))
  if send_result.code ~= 0 then
    return { tag = "failed", message = fail_message(send_result.code, send_result.stderr, "send") }
  end

  local focus_result = run(argv_focus(program.binding, program.label))
  if focus_result.code ~= 0 then
    return { tag = "failed", message = fail_message(focus_result.code, focus_result.stderr, "focus") }
  end

  return { tag = "ok" }
end

return M
