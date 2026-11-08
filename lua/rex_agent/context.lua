local seal, mention = ...
if seal ~= "rex-agent/sealed-v1" then
  error("rex_agent.context is internal; call require('rex_agent').ask()", 2)
end

local M = {}

---@param agent AgentConfig
---@return AgentConfig
local function copy_config(agent)
  local argv = {}
  for i, v in ipairs(agent.argv) do
    argv[i] = v
  end
  return { argv = argv, label = agent.label, pane = agent.pane }
end

---@return EditorCapture
function M.capture()
  if vim.bo.buftype ~= "" then
    return { tag = "blocked", reason = "Agent seed needs a saved file buffer" }
  end

  local name = vim.api.nvim_buf_get_name(0)
  if name == "" or name:match("^%w+://") then
    return { tag = "blocked", reason = "Agent seed needs a saved file buffer" }
  end

  local path = vim.fn.fnamemodify(name, ":p")
  if path:find("\n") or path:find("\r") then
    return { tag = "blocked", reason = "Agent seed needs a saved file buffer" }
  end

  if vim.bo.modified or vim.fn.filereadable(path) ~= 1 then
    return { tag = "blocked", reason = "Save the buffer before seeding the agent" }
  end

  local server = vim.env.REX_SERVER
  local session = vim.env.REX_SESSION
  local anchor = vim.env.REX_BLOCK
  if not server or server == "" or not session or session == "" or not anchor or anchor == "" then
    return { tag = "blocked", reason = "Neovim is not running inside a Rex session" }
  end

  local cwd = vim.uv.cwd()
  if not cwd then
    return { tag = "blocked", reason = "Neovim has no working directory" }
  end

  local mode = vim.api.nvim_get_mode().mode
  local first
  local last
  if mode == "v" or mode == "V" or mode == "\22" then
    local pos_v = vim.fn.getpos("v")
    local pos_dot = vim.fn.getpos(".")
    first = math.min(pos_v[2], pos_dot[2])
    last = math.max(pos_v[2], pos_dot[2])
    vim.cmd("normal! \27")
  else
    local line = vim.api.nvim_win_get_cursor(0)[1]
    first = line
    last = line
  end

  local seed, reason = mention.prepare(path, cwd, { first = first, last = last })
  if not seed then
    return { tag = "blocked", reason = reason }
  end

  return {
    tag = "ready",
    binding = {
      server = server,
      session = session,
      anchor = anchor,
    },
    cwd = cwd,
    seed = seed,
  }
end

---@param capture EditorCapture
---@param agent? AgentConfig
---@return AskFacts
function M.assemble(capture, agent)
  if capture.tag == "blocked" then
    return { tag = "blocked", reason = capture.reason }
  end

  if not agent then
    error("assemble: ready capture requires an agent")
  end

  return {
    tag = "ready",
    binding = capture.binding,
    cwd = capture.cwd,
    seed = capture.seed,
    config = copy_config(agent),
  }
end

return M
