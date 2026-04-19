local M = {}

local cfg = require("rvpm.config")

-- Canonical ex-commands for the built-in opener shortcuts.
local SHORTCUTS = {
  split   = "new",
  hsplit  = "new",
  vsplit  = "vnew",
  tabnew  = "tabnew",
  tab     = "tabnew",
}

local function open_float(title)
  local opts = cfg.options.terminal
  local cols = math.floor(vim.o.columns * opts.width)
  local rows = math.floor(vim.o.lines * opts.height)
  local col = math.floor((vim.o.columns - cols) / 2)
  local row = math.floor((vim.o.lines - rows) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = cols,
    height = rows,
    col = col,
    row = row,
    style = "minimal",
    border = opts.border,
    title = " " .. title .. " ",
    title_pos = "center",
  })
end

---Resolve the opener into a current-window side effect.
---After this returns, `nvim_get_current_{win,buf}` should point at the
---window/buffer jobstart will take over with `term = true`.
---@param opener string|fun()
---@param title string
local function spawn_host(opener, title)
  if type(opener) == "function" then
    opener()
    return
  end
  if opener == "float" then
    open_float(title)
    return
  end
  local shortcut = SHORTCUTS[opener]
  if shortcut then
    vim.cmd(shortcut)
    return
  end
  -- Anything else is treated as a user-supplied ex-command.
  vim.cmd(opener)
end

---Open an rvpm subcommand in the configured host window.
---@param args string[]
function M.open(args)
  local opener = cfg.options.terminal.opener or "float"
  local title = "rvpm " .. table.concat(args, " ")

  spawn_host(opener, title)

  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  -- For non-float hosts the window has no title; stamp the buffer name
  -- instead so it shows up as `rvpm://list` etc. in statuslines / tablines.
  if opener ~= "float" then
    pcall(vim.api.nvim_buf_set_name, buf, "rvpm://" .. table.concat(args, " "))
  end

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
            title .. " exited " .. code,
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
