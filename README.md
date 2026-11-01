# rex-agent.nvim

Open or reuse a Rex side pane from Neovim, start a configurable agent (`pi` by default), and seed the current file plus line range without submitting Enter.

Requires Neovim running inside [Rex](https://www.superlogical.com/rex) (`REX_SESSION`, `REX_BLOCK`, `REX_SERVER` in the process environment).

## Install (lazy.nvim)

On any machine with this repo available over git:

```lua
-- lua/plugins/rex-agent.lua
local dir = vim.fn.expand("~/projects/rexproject/rex-agent.nvim")

local plugin = {
  "athul-ramesh/rex-agent.nvim",
  main = "rex_agent",
  opts = {},
}

-- Prefer a local clone when present; otherwise lazy clones from GitHub.
if vim.fn.isdirectory(dir) == 1 then
  plugin.dir = dir
end

return {
  plugin,
  -- Optional: free visual <leader>as from LazyVim ClaudeCodeSend
  {
    "coder/claudecode.nvim",
    optional = true,
    keys = {
      { "<leader>as", false, mode = "v" },
    },
  },
}
```


## Usage

Press `<leader>as` in normal or visual mode on a **saved** file buffer.

- First press creates a right split labeled `nvim-agent` and starts the agent.
- Later presses reuse that pane, seed context again, and focus it.
- You finish the prompt and press Enter yourself.

## Options

```lua
require("rex_agent").setup({
  agent = { "pi" }, -- or a string, or another argv list
  label = "nvim-agent",
  keys = "<leader>as", -- or false to skip the default map
})
```

With lazy.nvim, pass the same fields through `opts`.

## Notes

- Unsaved or non-file buffers are refused.
- Neovim outside Rex is refused.
- `pi` 1.4.0 does not support `@path#L…`; the seed is `@path path:N-M `.
