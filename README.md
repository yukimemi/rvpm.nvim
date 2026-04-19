# rvpm.nvim

> Neovim helper for [rvpm](https://github.com/yukimemi/rvpm) — run the CLI from inside Neovim.

`rvpm` is intentionally CLI-first. `rvpm.nvim` is a thin Lua layer that
makes common operations available without leaving the editor:

- `:Rvpm <sub>` dispatches to the `rvpm` binary (async via `vim.system`, or
  in a floating terminal for interactive TUIs)
- Completion of plugin names from `config.toml`
- Auto-run `rvpm generate` when you save `config.toml` or any hook file
- `:RvpmAddCursor` to add the `owner/repo` under the cursor
- `:checkhealth rvpm` wraps `rvpm doctor`
- Dedicated log viewer buffer with `BREAKING` highlight

## Requirements

- Neovim 0.10+ (needs `vim.system`)
- [`rvpm`](https://github.com/yukimemi/rvpm) on your `PATH`

## Installation

Quickest — let `rvpm` itself add the entry and sync:

```sh
rvpm add yukimemi/rvpm.nvim
```

Or edit `config.toml` directly. **Minimal (eager, default)** — `:Rvpm`
is available on startup and the auto-generate autocmd is registered:

```toml
[[plugins]]
url = "yukimemi/rvpm.nvim"
```

**Lazy on `:Rvpm` invocation** — skip startup cost, at the expense of
the auto-generate autocmd (set `auto_generate = false` in the hook
below to suppress the warning):

```toml
[[plugins]]
url    = "yukimemi/rvpm.nvim"
on_cmd = ["Rvpm", "RvpmAddCursor"]
```

**With an explicit `setup()`** — drop a per-plugin hook at
`~/.config/rvpm/<appname>/plugins/github.com/yukimemi/rvpm.nvim/after.lua`:

```lua
require("rvpm").setup({
  notify = true,
  auto_generate = true,
  terminal = { border = "rounded" },
})
```

`setup()` is **optional** — `:Rvpm` and `:RvpmAddCursor` register
eagerly via `plugin/rvpm.lua` regardless. Call `setup()` only to tweak
defaults or opt out of auto-generate.

> `auto_generate = true` requires the plugin to be loaded before you
> save `config.toml`, so it's incompatible with `on_cmd` lazy-loading.
> Use the minimal eager form if you want the autocmd.

## Commands

| Command | What it does |
|---|---|
| `:Rvpm` | Open `rvpm list` TUI in a floating terminal |
| `:Rvpm sync [flags]` | Async `rvpm sync`, notify on completion |
| `:Rvpm generate` | Async `rvpm generate` |
| `:Rvpm clean` | Async `rvpm clean` |
| `:Rvpm add <repo>` | Floating-terminal `rvpm add` (interactive confirm) |
| `:Rvpm update [name]` | Floating-terminal `rvpm update` |
| `:Rvpm remove [name]` | Floating-terminal `rvpm remove` |
| `:Rvpm edit [name] [--init\|--before\|--after] [--global]` | Edit hooks |
| `:Rvpm set [name] [flags]` | `rvpm set` (interactive when no flags) |
| `:Rvpm config` | Open `config.toml` via `rvpm config` |
| `:Rvpm list` | TUI plugin list |
| `:Rvpm browse` | TUI plugin browser |
| `:Rvpm doctor` | Async `rvpm doctor`, output in notification |
| `:Rvpm log [name] [--last N] [--diff]` | Log in a dedicated buffer |
| `:RvpmAddCursor` | Pick up `owner/repo` under cursor → `rvpm add` |

Completion covers subcommands and plugin names from `config.toml`.

## Lua API

```lua
local rvpm = require("rvpm")

rvpm.sync()                          -- async sync, notify on completion
rvpm.generate()
rvpm.add("folke/snacks.nvim")
rvpm.list()                           -- open TUI
rvpm.browse()
rvpm.log({ "--last", "5", "--diff" })
rvpm.doctor()
```

## Configuration

Defaults:

```lua
require("rvpm").setup({
  cmd = "rvpm",          -- path to the rvpm binary
  auto_generate = true,  -- run `rvpm generate` on BufWritePost of config.toml / hooks
  notify = true,         -- vim.notify on CLI completion
  terminal = {
    opener = "float",    -- "float" | "split" | "vsplit" | "tabnew" | any ex-command | function
    -- float-only sizing:
    width  = 0.9,
    height = 0.9,
    border = "rounded",
  },
  config_root = nil,     -- override; default = ~/.config/rvpm/<appname>
})
```

### `terminal.opener`

Controls where the interactive TUIs (`list` / `browse` / `edit` / …) are
hosted. Accepts:

| Value | Effect |
|---|---|
| `"float"` *(default)* | Centered floating window using `terminal.{width,height,border}` |
| `"split"` / `"hsplit"` | `:new` — horizontal split below |
| `"vsplit"` | `:vnew` — vertical split to the left |
| `"tabnew"` / `"tab"` | `:tabnew` — fresh tab |
| any other string | Passed to `vim.cmd()` verbatim — e.g. `"botright 20split"`, `"enew"`, `"enew!"` |
| `function()` | Called directly; must leave a usable window current when it returns |

Reusing the current window (e.g. `opener = "enew"`) is supported:
`rvpm.nvim` detects that no new window was created and, on exit,
restores the buffer that was there before instead of closing the
window. If `:enew` fails because the current buffer is modified and
`&hidden` is off, the invocation is aborted with an error notification
(use `"enew!"` to force through).

Examples:

```lua
-- Open TUIs in a 20-line split at the bottom
require("rvpm").setup({ terminal = { opener = "botright 20split" } })

-- Or hand full control to a function
require("rvpm").setup({
  terminal = {
    opener = function()
      vim.cmd("tabnew")
      vim.wo.number = false
    end,
  },
})
```

Non-float hosts get the buffer named `rvpm://<args>` so the session shows
up cleanly in statuslines and tablines. The buffer is wiped on process
exit along with the window.

`<appname>` follows `rvpm`'s own rule:
`$RVPM_APPNAME` → `$NVIM_APPNAME` → `"nvim"`.

## Auto-generate details

When `auto_generate = true`, `rvpm.nvim` registers a `BufWritePost`
autocmd that runs `rvpm generate` (silently, errors still surface) when
any of these files is saved under `config_root`:

- `config.toml`
- `before.lua` / `after.lua` (global hooks)
- `plugins/<host>/<owner>/<repo>/(init|before|after).lua` (per-plugin hooks)

The intent is to keep the compiled `loader.lua` in sync with whatever
you just edited, matching the CLI workflow where `rvpm generate`
follows each edit.

## chezmoi integration

`rvpm`'s CLI-side writes (`rvpm add` / `set` / `remove` / `edit` / …)
already flow through chezmoi when `[options].chezmoi = true` — no
additional wiring is needed. Since `:Rvpm <sub>` dispatches to the same
binary, those paths are already covered.

`rvpm.nvim` also fills the **one gap** that pure CLI usage doesn't hit:
when you edit `config.toml` or a hook file directly from Neovim, the
`:w` lands on the chezmoi *target*, leaving the source state stale.
On `BufWritePost`, if `[options].chezmoi = true` and the file is
chezmoi-managed:

1. `chezmoi source-path <file>` — resolve the managed source (skip silently if unmanaged)
2. `chezmoi re-add --force <file>` — push the target edit back into source state
3. `rvpm generate` — regenerate `loader.lua`

Parity with `rvpm`'s own behavior:

- `.tmpl` sources are skipped with a warning (Tera lives in `rvpm`, not chezmoi)
- If `chezmoi` is missing from `PATH`, the step no-ops and `rvpm generate` still runs
- Files whose ancestors aren't managed by chezmoi are left alone

`:checkhealth rvpm` reports whether the integration is active.

## Health check

```
:checkhealth rvpm
```

Reports:

- `rvpm` binary presence + resolved path
- `config_root` and `config.toml` existence
- `rvpm doctor` exit status and full output

## License

MIT — see [LICENSE](LICENSE).
