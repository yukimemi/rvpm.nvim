local M = {}

local cli = require("rvpm.cli")
local term = require("rvpm.terminal")
local cfg = require("rvpm.config")
local log = require("rvpm.log")

local SUBCOMMANDS = {
  "sync", "generate", "clean", "add", "tune", "update", "remove",
  "edit", "set", "config", "init", "list", "browse",
  "doctor", "profile", "log",
}

-- Subcommands that drop into an interactive TUI / $EDITOR, routed through
-- the floating terminal so Neovim's UI doesn't fight the child process.
local TUI = {
  list = true,
  browse = true,
  config = true,
  edit = true,
  set = true,
  remove = true,
  update = true,
  add = true,
  tune = true,
  profile = true,
}

local PLUGIN_ARG_SUBS = {
  remove = true, update = true, edit = true, set = true, tune = true, log = true,
}

-- Per-subcommand option flags. Hardcoded mirror of `rvpm <sub> --help`.
-- Keep in sync with the rvpm CLI when flags are added/renamed.
local FLAGS = {
  sync    = { "--prune", "--frozen", "--no-lock", "--rebuild", "--refresh", "--no-refresh" },
  add     = {
    "--name", "--lazy", "--on-cmd", "--on-ft", "--on-map", "--on-event", "--rev",
    "--auto-lazy", "--no-lazy", "--ai", "--no-ai",
  },
  tune    = { "--ai", "--no-ai" },
  edit    = { "--init", "--before", "--after", "--global" },
  set     = {
    "--lazy", "--merge", "--on-cmd", "--on-ft", "--on-map", "--on-event",
    "--on-path", "--on-source", "--rev",
  },
  list    = { "--no-tui" },
  init    = { "--write" },
  profile = { "--runs", "--top", "--json", "--no-tui", "--no-merge", "--no-instrument" },
  log     = { "--last", "--full", "--diff" },
}

local function filter_prefix(items, prefix)
  return vim.tbl_filter(function(s)
    return s:sub(1, #prefix) == prefix
  end, items)
end

local function complete(arg_lead, cmd_line, _cursor_pos)
  local parts = vim.split(vim.trim(cmd_line), "%s+")
  local has_trailing_space = cmd_line:match("%s$") ~= nil
  local position = #parts + (has_trailing_space and 1 or 0)

  if position <= 2 then
    return filter_prefix(SUBCOMMANDS, arg_lead)
  end

  local sub = parts[2]

  -- Plugin-name slot: second positional for remove/update/edit/set/tune/log.
  -- Skip if the user is starting a flag (`-`).
  if PLUGIN_ARG_SUBS[sub] and position == 3 and arg_lead:sub(1, 1) ~= "-" then
    return filter_prefix(cfg.plugin_names(), arg_lead)
  end

  -- Flag completion: explicit `-` prefix, or empty arg in any non-plugin slot.
  -- Empty-arg fallback shows what's available for flag-only subs (sync/profile/...)
  -- and for the trailing slot of plugin-arg subs (tune <plugin> <Tab>).
  if arg_lead:sub(1, 1) == "-" or arg_lead == "" then
    return filter_prefix(FLAGS[sub] or {}, arg_lead)
  end

  return {}
end

local function dispatch(opts)
  local fargs = opts.fargs
  if #fargs == 0 then
    term.open({ "list" })
    return
  end

  local sub = fargs[1]
  local rest = vim.list_slice(fargs, 2)

  -- `log` always goes to a dedicated buffer viewer, even without args.
  if sub == "log" then
    log.show(rest)
    return
  end

  local argv = { sub }
  vim.list_extend(argv, rest)

  if TUI[sub] then
    term.open(argv)
  else
    cli.run(argv)
  end
end

local function add_from_cursor()
  local word = vim.fn.expand("<cfile>")
  if word == "" then
    word = vim.fn.expand("<cword>")
  end
  local owner_repo = word:match("github%.com[:/]([%w%._%-]+/[%w%._%-]+)")
    or word:match("^([%w%._%-]+/[%w%._%-]+)$")
  if not owner_repo then
    vim.notify(
      "No owner/repo under cursor (got: " .. word .. ")",
      vim.log.levels.WARN,
      { title = "rvpm" }
    )
    return
  end
  owner_repo = owner_repo:gsub("%.git$", "")
  cli.run({ "add", owner_repo })
end

function M.register()
  vim.api.nvim_create_user_command("Rvpm", dispatch, {
    nargs = "*",
    complete = complete,
    desc = "Run rvpm subcommand (TUI ones open in a floating terminal)",
  })

  vim.api.nvim_create_user_command("RvpmAddCursor", add_from_cursor, {
    desc = "rvpm add for the owner/repo under the cursor",
  })
end

return M
