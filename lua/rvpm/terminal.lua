local M = {}

local cfg = require("rvpm.config")

---Open an rvpm subcommand in a centered floating terminal.
---On exit, the floating window is closed and `checktime` re-reads any buffer
---the TUI may have edited (config.toml, hook files).
---@param args string[]
function M.open(args)
  local opts = cfg.options.terminal
  local cols = math.floor(vim.o.columns * opts.width)
  local rows = math.floor(vim.o.lines * opts.height)
  local col = math.floor((vim.o.columns - cols) / 2)
  local row = math.floor((vim.o.lines - rows) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = cols,
    height = rows,
    col = col,
    row = row,
    style = "minimal",
    border = opts.border,
    title = " rvpm " .. table.concat(args, " ") .. " ",
    title_pos = "center",
  })

  local cmd = { cfg.options.cmd }
  vim.list_extend(cmd, args)

  vim.fn.jobstart(cmd, {
    term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
        vim.cmd("checktime")
        if code ~= 0 and cfg.options.notify then
          vim.notify(
            "rvpm " .. table.concat(args, " ") .. " exited " .. code,
            vim.log.levels.WARN,
            { title = "rvpm" }
          )
        end
      end)
    end,
  })

  vim.cmd("startinsert")
end

return M
