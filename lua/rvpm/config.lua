local M = {}

---@class rvpm.Options
---@field cmd string                 Path to the `rvpm` binary. Defaults to "rvpm".
---@field auto_generate boolean      Run `rvpm generate` on BufWritePost of config.toml / hook files.
---@field notify boolean             Emit vim.notify messages on CLI completion.
---@field terminal rvpm.TerminalOpts Floating terminal sizing for TUI subcommands.
---@field config_root string|nil     Override for the config root. Nil = derive from $NVIM_APPNAME.

---@class rvpm.TerminalOpts
---@field width number               Fraction of editor width (0..1).
---@field height number              Fraction of editor height (0..1).
---@field border string              Border style passed to nvim_open_win.

M.defaults = {
  cmd = "rvpm",
  auto_generate = true,
  notify = true,
  terminal = {
    width = 0.9,
    height = 0.9,
    border = "rounded",
  },
  config_root = nil,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

function M.appname()
  return vim.env.RVPM_APPNAME or vim.env.NVIM_APPNAME or "nvim"
end

function M.config_root()
  if M.options.config_root then
    return vim.fn.expand(M.options.config_root)
  end
  local home = vim.env.HOME or vim.env.USERPROFILE or ""
  return (home .. "/.config/rvpm/" .. M.appname()):gsub("\\", "/")
end

function M.config_toml()
  return M.config_root() .. "/config.toml"
end

-- Extract plugin display names from config.toml for completion.
-- Minimal TOML scan: picks up `name` and `url` under [[plugins]] blocks.
-- Tera templates ({% if %}, {{ vars.x }}) are not expanded; a superset list
-- is fine for completion.
function M.plugin_names()
  local path = M.config_toml()
  local fd = io.open(path, "r")
  if not fd then
    return {}
  end
  local names = {}
  local in_plugins = false
  local current_name, current_url
  local function flush()
    if not in_plugins then
      return
    end
    if current_name then
      table.insert(names, current_name)
    elseif current_url then
      local leaf = current_url:match("([^/]+)$") or current_url
      leaf = leaf:gsub("%.git$", "")
      table.insert(names, leaf)
    end
    current_name, current_url = nil, nil
  end
  for line in fd:lines() do
    local header = line:match("^%s*%[%[%s*(.-)%s*%]%]")
    if header then
      flush()
      in_plugins = header == "plugins"
    elseif line:match("^%s*%[") then
      flush()
      in_plugins = false
    elseif in_plugins then
      local k, v = line:match('^%s*([%w_]+)%s*=%s*"([^"]*)"')
      if k == "name" then
        current_name = v
      elseif k == "url" then
        current_url = v
      end
    end
  end
  flush()
  fd:close()
  return names
end

return M
