local M = {}

local cfg = require("rvpm.config")

---Run rvpm with args asynchronously.
---
---`detach=true` makes the spawned `rvpm` survive the parent Neovim/Neovide
---process exit (Linux: `setsid`, Windows: `DETACHED_PROCESS`). Used by the
---BufWritePost auto-generate path so a `:wq!` (or any editor crash mid-run)
---does not interrupt a long `rvpm generate` and leave a half-written
---`loader.lua`. The completion callback may not fire when the parent exits
---first, so callers that rely on `notify=true` user feedback should not pass
---`detach=true` (interactive `:Rvpm sync` keeps the default).
---@param args string[]
---@param opts? { silent?: boolean, detach?: boolean, on_exit?: fun(result: vim.SystemCompleted) }
function M.run(args, opts)
  opts = opts or {}
  local cmd = { cfg.options.cmd }
  vim.list_extend(cmd, args)
  local label = "rvpm " .. table.concat(args, " ")
  local notify = cfg.options.notify

  if notify and not opts.silent then
    vim.notify(label .. " …", vim.log.levels.INFO, { title = "rvpm" })
  end

  local system_opts = { text = true, detach = opts.detach == true }
  vim.system(cmd, system_opts, function(result)
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
