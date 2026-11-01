local M = {}

local SEAL = "rex-agent/sealed-v1"

---@type AgentConfig
local config = {
  argv = { "pi" },
  label = "nvim-agent",
  keys = "<leader>as",
}

local program = nil
local rex = nil
local context = nil
local keys_bound = false

local function private_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("(.*)/[^/]+$") or "."
end

local function private(name)
  local path = private_dir() .. "/" .. name .. ".lua"
  local loader, err = loadfile(path)
  if not loader then
    error(err)
  end
  return loader(SEAL)
end

---@param argv string[]
---@return boolean
local function valid_argv(argv)
  if type(argv) ~= "table" or #argv == 0 then
    return false
  end
  for _, part in ipairs(argv) do
    if type(part) ~= "string" or part == "" or part:find("\n") or part:find("\r") then
      return false
    end
  end
  return true
end

---@param label string
---@return boolean
local function valid_label(label)
  return type(label) == "string" and label:match("^[%w_.:-]+$") ~= nil
end

local function bind_keys(lhs)
  if keys_bound or not lhs then
    return
  end
  vim.keymap.set({ "n", "v" }, lhs, function()
    M.ask()
  end, { desc = "Seed agent pane", silent = true })
  keys_bound = true
end

---@param opts? { agent?: string|string[], label?: string, keys?: string|false }
function M.setup(opts)
  opts = opts or {}

  local next_config = {
    argv = config.argv,
    label = config.label,
    keys = config.keys,
  }

  if opts.agent ~= nil then
    if type(opts.agent) == "string" then
      next_config.argv = { opts.agent }
    elseif type(opts.agent) == "table" then
      next_config.argv = opts.agent
    else
      vim.notify("rex_agent.setup: agent must be a string or list of strings", vim.log.levels.ERROR)
      return
    end
  end

  if opts.label ~= nil then
    next_config.label = opts.label
  end

  if opts.keys ~= nil then
    if opts.keys == false then
      next_config.keys = false
    elseif type(opts.keys) == "string" and opts.keys ~= "" then
      next_config.keys = opts.keys
    else
      vim.notify("rex_agent.setup: keys must be a string or false", vim.log.levels.ERROR)
      return
    end
  end

  if not valid_argv(next_config.argv) then
    vim.notify("rex_agent.setup: agent argv must be a non-empty list of strings", vim.log.levels.ERROR)
    return
  end

  if not valid_label(next_config.label) then
    vim.notify("rex_agent.setup: label must match [%w_.:-]+", vim.log.levels.ERROR)
    return
  end

  config = next_config
  if config.keys then
    bind_keys(config.keys)
  end
end

function M.ask()
  local facts = context.read_editor(config)
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

context = private("context")
program = private("program")
rex = private("rex")

return M
