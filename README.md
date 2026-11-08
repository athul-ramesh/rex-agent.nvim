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

## Options

Pass fields through lazy `opts`, or call setup directly:

```lua
require("rex_agent").setup({
  agent = { "pi" }, -- string or argv list
  label = "nvim-agent",
  keys = "<leader>as", -- or false to skip the default map
})
```

## Notes

- Unsaved or non-file buffers are refused.
- Neovim outside Rex is refused.
- Files outside Neovim's working directory, paths with `#`, or `.` / `..` segments are refused.
- The agent executable is resolved with Neovim's `exepath` before create, because Rex `shell=none` does not see Homebrew PATH.
