local seal = ...
if seal ~= "rex-agent/sealed-v1" then
  error("rex_agent.mention is internal; call require('rex_agent').ask()", 2)
end

local M = {}

local FORMAT = {
  line = function(seed)
    return "@" .. seed.rel.text .. "#L" .. seed.span.first .. " "
  end,
  range = function(seed)
    return "@" .. seed.rel.text .. "#L" .. seed.span.first .. "-" .. seed.span.last .. " "
  end,
}

---@param rel string
---@return boolean
local function bad_segments(rel)
  for segment in rel:gmatch("[^/]+") do
    if segment == "." or segment == ".." then
      return true
    end
  end
  return false
end

---@param abs string
---@param cwd string
---@param span { first: integer, last: integer }
---@return Seed|nil seed
---@return string|nil reason
function M.prepare(abs, cwd, span)
  if span.first < 1 or span.last < span.first then
    error("mention.prepare: span invariant", 2)
  end

  local file_real = vim.uv.fs_realpath(abs)
  local cwd_real = vim.uv.fs_realpath(cwd)
  if not file_real or not cwd_real then
    return nil, "Agent seed file is outside Neovim's working directory"
  end

  local prefix = cwd_real:gsub("/+$", "") .. "/"
  if file_real ~= cwd_real:gsub("/+$", "") and file_real:sub(1, #prefix) ~= prefix then
    return nil, "Agent seed file is outside Neovim's working directory"
  end

  local rel
  if file_real == cwd_real:gsub("/+$", "") then
    rel = ""
  else
    rel = file_real:sub(#prefix + 1)
  end

  if rel == "" or rel:sub(1, 1) == "/" then
    return nil, "Agent seed file is outside Neovim's working directory"
  end
  if rel:find("#", 1, true) or rel:find("\n") or rel:find("\r") then
    if rel:find("#", 1, true) then
      return nil, "Agent seed path cannot contain '#'"
    end
    return nil, "Agent seed file is outside Neovim's working directory"
  end
  if bad_segments(rel) then
    return nil, "Agent seed file is outside Neovim's working directory"
  end

  return {
    rel = { text = rel },
    span = { first = span.first, last = span.last },
  }
end

---@param seed Seed
---@return string
function M.format(seed)
  local key = "range"
  if seed.span.first == seed.span.last then
    key = "line"
  end
  return FORMAT[key](seed)
end

return M
