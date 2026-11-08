local seal, mention, ready = ...
if seal ~= "rex-agent/sealed-v1" then
  error("rex_agent.rex is internal; call require('rex_agent').ask()", 2)
end

local M = {}

local FLOAT_BOUNDS = { 0.58, 0.08, 0.38, 0.84 }

---@param argv string[]
---@return integer|nil code
---@return string stdout
---@return string stderr
local function run(argv)
  local obj = vim.system(argv, { text = true })
  local result = obj:wait()
  return result.code, result.stdout or "", result.stderr or ""
end

---@param code integer|nil
---@param stderr string
---@param what string
---@return string
local function fail_message(code, stderr, what)
  local detail = stderr:match("%S") and stderr:gsub("%s+$", "") or ("exit " .. tostring(code))
  return "rex " .. what .. " failed: " .. detail
end

---@param binding RexBinding
---@return table|nil view
---@return string|nil err
local function session_view(binding)
  local code, stdout, stderr = run({
    "rex",
    "--server",
    binding.server,
    "api",
    "call",
    "-s",
    binding.session,
    "session.view",
  })
  if code ~= 0 then
    return nil, fail_message(code, stderr, "session.view")
  end
  local ok, decoded = pcall(vim.json.decode, stdout)
  if not ok or type(decoded) ~= "table" then
    return nil, "rex session.view failed: invalid JSON"
  end
  return decoded
end

---@param binding RexBinding
---@param label string
---@return PaneSight
local function classify(binding, label)
  local view, err = session_view(binding)
  if not view then
    return { tag = "failed", message = err }
  end

  local anchor_window_id
  local hits = {}

  for _, win in ipairs(view.windows or {}) do
    for _, layer in ipairs(win.layers or {}) do
      for _, block in ipairs(layer.blocks or {}) do
        if block.block_id == binding.anchor then
          anchor_window_id = win.window_id
        end
        if block.label == label then
          hits[#hits + 1] = { layer = layer, block = block }
        end
      end
    end
  end

  if #hits == 0 then
    if not anchor_window_id then
      return { tag = "failed", message = "rex session.view failed: anchor block not in layout" }
    end
    return { tag = "absent", window_id = anchor_window_id }
  end
  if #hits > 1 then
    return { tag = "failed", message = "rex focus failed: agent label is ambiguous" }
  end

  local hit = hits[1]
  if hit.layer.kind == "tiled" then
    return { tag = "tiled", block_id = hit.block.block_id }
  end
  return { tag = "floating", block_id = hit.block.block_id }
end

---@param program ProbeProgram
---@return PaneSight
function M.probe(program)
  return classify(program.binding, program.label)
end

---@param binding RexBinding
---@param method string
---@param args table
---@return EnactResult
local function api_call(binding, method, args)
  local code, _, stderr = run({
    "rex",
    "--server",
    binding.server,
    "api",
    "call",
    "-s",
    binding.session,
    method,
    vim.json.encode(args),
  })
  if code == 0 then
    return { tag = "ok" }
  end
  return { tag = "failed", message = fail_message(code, stderr, method) }
end

--- Rex `shell=none` uses the server PATH, which omits Homebrew. Absolute agent
--- paths still need that PATH for shebangs such as `#!/usr/bin/env node`.
---@param argv string[]
---@return string[]|nil command
---@return string[]|nil path_prepend
---@return string|nil err
local function resolve_launch(argv)
  local command = {}
  for i, part in ipairs(argv) do
    command[i] = part
  end
  local exe = command[1]
  if exe and exe:sub(1, 1) ~= "/" then
    local found = vim.fn.exepath(exe)
    if found == "" then
      return nil, nil, "Agent executable not found on Neovim PATH: " .. exe
    end
    command[1] = found
  end

  local seen = {}
  local path_prepend = {}
  for dir in string.gmatch(vim.env.PATH or "", "([^:]+)") do
    if dir ~= "" and not seen[dir] then
      seen[dir] = true
      path_prepend[#path_prepend + 1] = dir
    end
  end
  return command, path_prepend
end

---@param program OpenProgram
---@return table|nil options
---@return string|nil err
local function shell_block_options(program)
  local command, path_prepend, err = resolve_launch(program.argv)
  if not command then
    return nil, err
  end
  local options = {
    command = command,
    cwd = program.cwd,
    shell = "none",
    exit = { on_completion = false },
  }
  if path_prepend and #path_prepend > 0 then
    options.path_prepend = path_prepend
  end
  return options
end

---@param program OpenProgram
---@return table|nil layout
---@return string|nil err
local function agent_shell_layout(program)
  local options, err = shell_block_options(program)
  if not options then
    return nil, err
  end
  return {
    block = {
      flavor = "com.superlogical.terminal.shell",
      label = program.label,
      options = options,
    },
  }
end

---@param program OpenProgram
---@return EnactResult
local function open_float(program)
  local layout, err = agent_shell_layout(program)
  if not layout then
    return { tag = "failed", message = err }
  end
  return api_call(program.binding, "session.new_layer", {
    window_id = program.window_id,
    bounds = FLOAT_BOUNDS,
    focus = false,
    layout = layout,
  })
end

---@param program OpenProgram
---@return EnactResult
local function open_split(program)
  local split = program.split
  if not split then
    return { tag = "failed", message = "rex open split failed: missing split spec" }
  end
  local layout, err = agent_shell_layout(program)
  if not layout then
    return { tag = "failed", message = err }
  end
  return api_call(program.binding, "session.new_split", {
    anchor_id = split.anchor_id,
    direction = split.direction,
    side = split.side,
    focus = false,
    layout = layout,
  })
end

---@param binding RexBinding
---@param block_id string
---@return EnactResult
local function float_block(binding, block_id)
  local placed = api_call(binding, "session.float_block", {
    block_id = block_id,
    bounds = FLOAT_BOUNDS,
  })
  if placed.tag == "ok" then
    return placed
  end

  local view = session_view(binding)
  if view then
    for _, win in ipairs(view.windows or {}) do
      for _, layer in ipairs(win.layers or {}) do
        if layer.kind ~= "tiled" then
          for _, block in ipairs(layer.blocks or {}) do
            if block.block_id == block_id then
              return { tag = "ok" }
            end
          end
        end
      end
    end
  end

  return placed
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

---@param program OpenProgram|RaiseProgram|ReuseProgram
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
    mention.format(program.seed),
  }
end

---@param program OpenProgram|RaiseProgram|ReuseProgram
---@return EnactResult
local function focus_program(program)
  local focus_code, _, focus_stderr = run(argv_focus(program.binding, program.label))
  if focus_code ~= 0 then
    return { tag = "failed", message = fail_message(focus_code, focus_stderr, "focus") }
  end
  return { tag = "ok" }
end

---@param program OpenProgram|RaiseProgram|ReuseProgram
---@return fun(): EnactResult
local function send_fn(program)
  return function()
    local send_code, _, send_stderr = run(argv_send(program))
    if send_code ~= 0 then
      return { tag = "failed", message = fail_message(send_code, send_stderr, "send") }
    end
    return { tag = "ok" }
  end
end

---@param program OpenProgram|RaiseProgram|ReuseProgram
---@return EnactResult
local function deliver_seed(program)
  return ready.ensure_seed(program.binding, program.label, program.seed, send_fn(program))
end

---@param program OpenProgram|RaiseProgram|ReuseProgram
---@return EnactResult
function M.enact(program)
  if program.tag == "open" then
    local placed
    if program.open_via == "split" then
      placed = open_split(program)
    else
      placed = open_float(program)
    end
    if placed.tag == "failed" then
      return placed
    end
    local focused = focus_program(program)
    if focused.tag == "failed" then
      return focused
    end
    return deliver_seed(program)
  end

  if program.tag == "raise" then
    local placed = float_block(program.binding, program.block_id)
    if placed.tag == "failed" then
      return placed
    end
    local focused = focus_program(program)
    if focused.tag == "failed" then
      return focused
    end
    return deliver_seed(program)
  end

  local focused = focus_program(program)
  if focused.tag == "failed" then
    return focused
  end
  return deliver_seed(program)
end

return M
