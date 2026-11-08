# rex-agent.nvim

Open or reuse a Rex floating agent pane from Neovim, start a configurable agent (`pi` by default), and seed the current file plus line range without submitting Enter.

Requires Neovim running inside [Rex](https://www.superlogical.com/rex) (`REX_SESSION`, `REX_BLOCK`, and `REX_SERVER` in the process environment).

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "athul-ramesh/rex-agent.nvim",
  main = "rex_agent",
  opts = {},
}
```

If LazyVim's Claude Code extra owns visual `<leader>as`, free that key:

```lua
{
  "coder/claudecode.nvim",
  optional = true,
  keys = {
    { "<leader>as", false, mode = "v" },
  },
}
```

## Usage

Press `<leader>as` in normal or visual mode on a saved file buffer.

- First press opens a floating layer labeled `nvim-agent` and starts the agent.
- Later presses reuse that floating pane, seed context again, and focus it.
- The seed is `@rel/path#L131 ` for one line and `@rel/path#L131-140 ` for a range, relative to Neovim's cwd. Finish the prompt and press Enter yourself.

With multiple profiles and no `default`, the main map opens an agent picker. Per-profile `keys` or `ask("name")` seed a specific agent without the picker.

## Options

Pass fields through lazy `opts`, or call setup directly.

### Legacy single agent

```lua
require("rex_agent").setup({
  agent = { "pi" }, -- string or argv list
  label = "nvim-agent",
  keys = "<leader>as", -- or false to skip the default map
})
```

Omitting `profiles` synthesizes one profile whose name is the label. The main map seeds it directly with no picker.

### Multiple profiles

```lua
require("rex_agent").setup({
  keys = "<leader>as",
  -- default = "pi", -- optional: main map and ask() skip the picker
  profiles = {
    { name = "pi", argv = { "pi" }, label = "pi" },
    {
      name = "claude",
      argv = { "claude" },
      label = "claude-code",
      keys = "<leader>ac", -- optional direct map for this profile
    },
    { name = "devin", argv = { "devin" }, label = "devin" },
  },
})
```

- `name` is the handle for `ask("name")`. `label` is the Rex block label.
- `argv` is a non-empty list of strings (command plus args).
- Per-profile `keys` bind that profile directly and skip the picker on that chord.
- `default` must name a profile. When set, `ask()` and the main map seed that profile with no picker.
- One profile and no `default` also skips the picker.
- `keys = false` on setup omits the main chooser map. Per-profile maps still bind.
- Do not pass `profiles` together with `agent` or `label`.

## Notes

- Unsaved or non-file buffers are refused.
- Neovim outside Rex is refused.
- Files outside Neovim's working directory, paths with `#`, or `.` / `..` segments are refused.
- Create uses `shell=none` with the agent resolved via Neovim `exepath`, and prepends Neovim's `PATH` so shebangs like `env node` still resolve.
