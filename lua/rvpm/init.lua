local M = {}

---@param opts? rvpm.Options
function M.setup(opts)
  local cfg = require("rvpm.config")
  cfg.setup(opts)
  require("rvpm.command").register()
  if cfg.options.auto_generate then
    require("rvpm.autocmd").register()
  end
end

-- Convenience Lua API: `require("rvpm").sync()` etc.
---@param args? string[]
function M.sync(args)
  local argv = { "sync" }
  vim.list_extend(argv, args or {})
  require("rvpm.cli").run(argv)
end

---@param args? string[]
function M.generate(args)
  local argv = { "generate" }
  vim.list_extend(argv, args or {})
  require("rvpm.cli").run(argv)
end

---@param repo string  owner/repo or full URL
function M.add(repo)
  require("rvpm.cli").run({ "add", repo })
end

function M.doctor()
  require("rvpm.cli").run({ "doctor" }, {
    silent = true,
    on_exit = function(r)
      local level = r.code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
      vim.notify(r.stdout or "", level, { title = "rvpm doctor" })
    end,
  })
end

function M.list()
  require("rvpm.terminal").open({ "list" })
end

function M.browse()
  require("rvpm.terminal").open({ "browse" })
end

---@param args? string[]
function M.tune(args)
  local argv = { "tune" }
  vim.list_extend(argv, args or {})
  require("rvpm.terminal").open(argv)
end

---@param args? string[]
function M.profile(args)
  local argv = { "profile" }
  vim.list_extend(argv, args or {})
  require("rvpm.terminal").open(argv)
end

---@param args? string[]
function M.log(args)
  require("rvpm.log").show(args)
end

return M
