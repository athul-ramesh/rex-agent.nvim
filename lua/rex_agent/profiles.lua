local seal = ...
if seal ~= "rex-agent/sealed-v1" then
  error("rex_agent.profiles is internal; call require('rex_agent').setup()", 2)
end

local M = {}

local DEFAULT_ARGV = { "pi" }
local DEFAULT_LABEL = "nvim-agent"
local DEFAULT_KEYS = "<leader>as"

local NAME_PATTERN = "^[%w_.:-]+$"

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

---@param token string
---@return boolean
local function valid_name_token(token)
  return type(token) == "string" and token:match(NAME_PATTERN) ~= nil
end

---@param argv string[]
---@return string[]
local function copy_argv(argv)
  local out = {}
  for i, v in ipairs(argv) do
    out[i] = v
  end
  return out
end

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

---@param opts? SetupOpts
---@return Plan|nil plan
---@return string|nil err
function M.build(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    return nil, "rex_agent.setup: opts must be a table"
  end

  local main_keys
  if opts.keys == nil then
    main_keys = DEFAULT_KEYS
  elseif opts.keys == false then
    main_keys = false
  elseif type(opts.keys) == "string" and opts.keys ~= "" then
    main_keys = opts.keys
  else
    return nil, "rex_agent.setup: keys must be a string or false"
  end

  local default_name = opts.default
  if default_name ~= nil and not valid_name_token(default_name) then
    return nil, "rex_agent.setup: default must match [%w_.:-]+"
  end

  local specs = {}

  if opts.profiles ~= nil then
    if opts.agent ~= nil or opts.label ~= nil then
      return nil, "rex_agent.setup: pass profiles or agent/label, not both"
    end
    if type(opts.profiles) ~= "table" or opts.profiles[1] == nil then
      return nil, "rex_agent.setup: profiles must be a non-empty list"
    end
    local n = #opts.profiles
    for i = 1, n do
      if opts.profiles[i] == nil then
        return nil, "rex_agent.setup: profiles must be a non-empty list"
      end
    end
    for _, entry in ipairs(opts.profiles) do
      if type(entry) ~= "table" then
        return nil, "rex_agent.setup: each profile must be a table"
      end
      local name = entry.name
      if not valid_name_token(name) then
        return nil, "rex_agent.setup: profile name must match [%w_.:-]+"
      end
      local label = entry.label
      if not valid_name_token(label) then
        return nil, "rex_agent.setup: profile label must match [%w_.:-]+"
      end
      local argv = entry.argv
      if not valid_argv(argv) then
        return nil, "rex_agent.setup: profile argv must be a non-empty list of strings"
      end
      local profile_keys = entry.keys
      if profile_keys ~= nil then
        if profile_keys == false then
          return nil, "rex_agent.setup: profile keys must be a string when set"
        end
        if type(profile_keys) ~= "string" or profile_keys == "" then
          return nil, "rex_agent.setup: profile keys must be a non-empty string"
        end
      end
      specs[#specs + 1] = {
        name = name,
        keys = profile_keys,
        argv = argv,
        label = label,
      }
    end
  else
    local argv = DEFAULT_ARGV
    if opts.agent ~= nil then
      if type(opts.agent) == "string" then
        argv = { opts.agent }
      elseif type(opts.agent) == "table" then
        argv = opts.agent
      else
        return nil, "rex_agent.setup: agent must be a string or list of strings"
      end
    end
    if not valid_argv(argv) then
      return nil, "rex_agent.setup: agent argv must be a non-empty list of strings"
    end
    local label = opts.label
    if label == nil then
      label = DEFAULT_LABEL
    elseif not valid_name_token(label) then
      return nil, "rex_agent.setup: label must match [%w_.:-]+"
    end
    specs[1] = {
      name = label,
      keys = nil,
      argv = argv,
      label = label,
    }
  end

  local profiles = {}
  local by_name = {}
  local seen_name = {}
  local seen_label = {}
  local seen_lhs = {}

  local function claim_lhs(lhs)
    if seen_lhs[lhs] then
      return false, string.format("rex_agent.setup: key '%s' is bound more than once", lhs)
    end
    seen_lhs[lhs] = true
    return true
  end

  if type(main_keys) == "string" then
    local ok, err = claim_lhs(main_keys)
    if not ok then
      return nil, err
    end
  end

  for _, spec in ipairs(specs) do
    if seen_name[spec.name] then
      return nil, string.format("rex_agent.setup: duplicate profile name '%s'", spec.name)
    end
    seen_name[spec.name] = true

    if seen_label[spec.label] then
      return nil, string.format("rex_agent.setup: duplicate label '%s'", spec.label)
    end
    seen_label[spec.label] = true

    if spec.keys then
      local ok, err = claim_lhs(spec.keys)
      if not ok then
        return nil, err
      end
    end

    local profile = {
      name = spec.name,
      keys = spec.keys,
      agent = {
        argv = copy_argv(spec.argv),
        label = spec.label,
      },
    }
    profiles[#profiles + 1] = profile
    by_name[spec.name] = profile
  end

  if default_name ~= nil and by_name[default_name] == nil then
    return nil, string.format("rex_agent.setup: default '%s' is not a profile name", default_name)
  end

  ---@type Catalog
  local catalog = {
    profiles = profiles,
    by_name = by_name,
    default_name = default_name,
  }

  return { catalog = catalog, main_keys = main_keys }
end

---@param catalog Catalog
---@param which? string
---@return Resolve
function M.resolve(catalog, which)
  if which ~= nil then
    if type(which) ~= "string" then
      return { tag = "reject", reason = "rex_agent.ask: profile name must be a string" }
    end
    local profile = catalog.by_name[which]
    if not profile then
      return { tag = "reject", reason = string.format("rex_agent.ask: unknown profile '%s'", which) }
    end
    return { tag = "chosen", agent = profile.agent }
  end

  if catalog.default_name then
    return { tag = "chosen", agent = catalog.by_name[catalog.default_name].agent }
  end

  if #catalog.profiles == 1 then
    return { tag = "chosen", agent = catalog.profiles[1].agent }
  end

  return { tag = "choose" }
end

---@param catalog Catalog
---@param on_agent fun(agent: AgentConfig)
function M.present(catalog, on_agent)
  local function format_item(profile)
    local argv_first = profile.agent.argv[1]
    if profile.name == profile.agent.label then
      return string.format("%s    %s", profile.name, argv_first)
    end
    return string.format("%s    %s    %s", profile.name, argv_first, profile.agent.label)
  end

  vim.ui.select(catalog.profiles, {
    prompt = "Agent",
    format_item = format_item,
  }, function(choice)
    if not choice then
      return
    end
    on_agent(choice.agent)
  end)
end

---@param plan Plan
---@param ask fun(which?: string)
---@return boolean bound
function M.bind(plan, ask)
  local catalog = plan.catalog
  local entries = {}

  if type(plan.main_keys) == "string" then
    local desc
    if catalog.default_name or #catalog.profiles == 1 then
      desc = "Seed agent pane"
    else
      desc = "Choose agent"
    end
    entries[#entries + 1] = { lhs = plan.main_keys, which = nil, desc = desc }
  end

  for _, profile in ipairs(catalog.profiles) do
    if profile.keys then
      entries[#entries + 1] = {
        lhs = profile.keys,
        which = profile.name,
        desc = string.format("Seed %s agent", profile.name),
      }
    end
  end

  if #entries == 0 then
    return false
  end

  for _, entry in ipairs(entries) do
    local which = entry.which
    vim.keymap.set({ "n", "v" }, entry.lhs, function()
      ask(which)
    end, { desc = entry.desc, silent = true })
  end

  return true
end

return M
