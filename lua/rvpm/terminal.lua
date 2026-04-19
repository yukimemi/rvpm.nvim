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

  local buf_before = vim.api.nvim_get_current_buf()
  local win_before = vim.api.nvim_get_current_win()

  spawn_host(opener, title)

  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  -- Safety: the opener must have created or switched to a fresh buffer.
  -- Otherwise jobstart(term=true) would convert the user's working
  -- buffer into a terminal. `:enew` fails silently when &hidden is off
  -- and the current buffer is modified — catch that here.
  if buf == buf_before then
    if cfg.options.notify then
      vim.notify(
        "rvpm.nvim: opener did not switch buffers — aborting (modified buffer? try `enew!`)",
        vim.log.levels.ERROR,
        { title = "rvpm" }
      )
    end
    return
  end

  local window_was_reused = (win == win_before)

  pcall(vim.api.nvim_buf_set_name, buf, "rvpm://" .. table.concat(args, " "))

  local cmd = { cfg.options.cmd }
  vim.list_extend(cmd, args)

  vim.fn.jobstart(cmd, {
    term = true,
    on_exit = function(_, code)
      vim.schedule(function()
        if window_was_reused then
          -- The opener took over the user's current window (e.g. `enew`).
          -- Don't close it — restore the buffer that was there before.
          if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf_before) then
            pcall(vim.api.nvim_win_set_buf, win, buf_before)
          end
        else
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
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
