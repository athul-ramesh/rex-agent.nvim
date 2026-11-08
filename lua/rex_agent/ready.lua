local seal, mention = ...
if seal ~= "rex-agent/sealed-v1" then
  error("rex_agent.ready is internal; call require('rex_agent').ask()", 2)
end

local M = {}

local TAIL_LINES = 30
local POLL_MS = 150
local DEADLINE_MS = 120000
local MAX_SENDS = 3

---@param seed Seed
---@return string
function M.needle_for_search(seed)
  return mention.format(seed):gsub("%s+$", "")
end

---@param text string
---@return string
function M.coarsen(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line:gsub("%s+$", "")
  end
  while #lines > 0 and lines[#lines] == "" do
    lines[#lines] = nil
  end
  local body = table.concat(lines, "\n")
  return body:gsub("%d+", "#")
end

---@param capture_text string
---@param needle string
---@param tail_n? integer
---@return boolean
function M.seed_visible_in_tail(capture_text, needle, tail_n)
  tail_n = tail_n or TAIL_LINES
  if needle == "" then
    return false
  end
  local nonempty = {}
  for line in capture_text:gmatch("[^\n]*") do
    if line:match("%S") then
      nonempty[#nonempty + 1] = line
    end
  end
  local start = math.max(1, #nonempty - tail_n + 1)
  for i = start, #nonempty do
    if nonempty[i]:find(needle, 1, true) then
      return true
    end
  end
  return false
end

---@param binding RexBinding
---@param label string
---@return string[]
local function argv_capture(binding, label)
  return {
    "rex",
    "--server",
    binding.server,
    "capture",
    "--session",
    binding.session,
    "--block",
    label,
    "--trim",
  }
end

---@param argv string[]
---@return integer|nil code
---@return string stdout
---@return string stderr
local function run(argv)
  local obj = vim.system(argv, { text = true })
  local result = obj:wait()
  return result.code, result.stdout or "", result.stderr or ""
end

---@param binding RexBinding
---@param label string
---@return string|nil capture
---@return string|nil err
local function fetch_capture(binding, label)
  local code, stdout, stderr = run(argv_capture(binding, label))
  if code ~= 0 then
    local detail = stderr:match("%S") and stderr:gsub("%s+$", "") or ("exit " .. tostring(code))
    return nil, "rex capture failed: " .. detail
  end
  return stdout, nil
end

---@param binding RexBinding
---@param label string
---@param seed Seed
---@param send_fn fun(): EnactResult
---@return EnactResult
function M.ensure_seed(binding, label, seed, send_fn)
  local needle = M.needle_for_search(seed)
  local deadline = vim.uv.now() + DEADLINE_MS
  local sends = 0
  local last_fp = nil

  while vim.uv.now() < deadline do
    local capture, cap_err = fetch_capture(binding, label)
    if not capture then
      return { tag = "failed", message = cap_err }
    end

    if M.seed_visible_in_tail(capture, needle) then
      return { tag = "ok" }
    end

    local fp = M.coarsen(capture)
    if fp ~= last_fp and sends < MAX_SENDS then
      local sent = send_fn()
      if sent.tag == "failed" then
        return sent
      end
      sends = sends + 1
      last_fp = fp
    elseif fp ~= last_fp then
      last_fp = fp
    end

    vim.wait(POLL_MS, function()
      return false
    end)
  end

  return { tag = "failed", message = "rex seed not visible after " .. tostring(DEADLINE_MS / 1000) .. "s" }
end

return M
