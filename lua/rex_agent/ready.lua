local seal, mention = ...
if seal ~= "rex-agent/sealed-v1" then
  error("rex_agent.ready is internal; call require('rex_agent').ask()", 2)
end

local M = {}

local TAIL_LINES = 30

---@param seed Seed
---@return string
function M.needle_for_search(seed)
  return mention.format(seed):gsub("%s+$", "")
end

---@param text string
---@return string
function M.coarsen(text)
  local lines = {}
  for line in text:gmatch("[^\n]*") do
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

return M
