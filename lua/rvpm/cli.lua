local M = {}

local cfg = require("rvpm.config")

---Run rvpm with args asynchronously.
---@param args string[]
---@param opts? { silent?: boolean, on_exit?: fun(result: vim.SystemCompleted) }
function M.run(args, opts)
  opts = opts or {}
  local cmd = { cfg.options.cmd }
  vim.list_extend(cmd, args)
  local label = "rvpm " .. table.concat(args, " ")
  local notify = cfg.options.notify

  if notify and not opts.silent then
    vim.notify(label .. " …", vim.log.levels.INFO, { title = "rvpm" })
  end

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      if notify then
        if result.code == 0 then
          if not opts.silent then
            vim.notify(label .. " ✓", vim.log.levels.INFO, { title = "rvpm" })
          end
        else
          local msg = (result.stderr and result.stderr ~= "" and result.stderr)
            or result.stdout
            or ""
          vim.notify(label .. " ✗\n" .. msg, vim.log.levels.ERROR, { title = "rvpm" })
        end
      end
      if opts.on_exit then
        opts.on_exit(result)
      end
    end)
  end)
end

---Synchronous variant used for completion prewarm; never blocks longer than timeout_ms.
---@param args string[]
---@param timeout_ms? integer
---@return string? stdout
---@return integer code
function M.run_sync(args, timeout_ms)
  local cmd = { cfg.options.cmd }
  vim.list_extend(cmd, args)
  local result = vim.system(cmd, { text = true }):wait(timeout_ms or 3000)
  return result.stdout, result.code
end

return M
