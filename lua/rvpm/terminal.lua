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

---True when `buf` is an empty, unnamed, unmodified buffer — safe to
---convert to a terminal even without a bufnr change. Used to distinguish
---`:enew!` on a reusable scratch (expected) from an accidental no-op
---opener that leaves a real file buffer current (dangerous).
---@param buf integer
---@return boolean
function M._buffer_is_empty_scratch(buf)
  if vim.bo[buf].modified then
    return false
  end
  if vim.api.nvim_buf_get_name(buf) ~= "" then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return #lines == 0 or (#lines == 1 and lines[1] == "")
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

  -- Safety: we're about to turn `buf` into a terminal. The dangerous case
  -- is when the opener left us on the same buffer *and* that buffer holds
  -- real work (named / modified / non-empty) — jobstart would clobber it.
  -- `:enew!` on an already-empty unnamed scratch buffer can keep the same
  -- bufnr (nvim reuses it); that's safe, so let it through.
  if buf == buf_before and not M._buffer_is_empty_scratch(buf) then
    if cfg.options.notify then
      vim.notify(
        "rvpm.nvim: opener left us in a non-empty / named / modified buffer — aborting",
        vim.log.levels.ERROR,
        { title = "rvpm" }
      )
    end
    return
  end

  local window_was_reused = (win == win_before)
  local have_prior_buf = (buf ~= buf_before)

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
          -- Skip restore when the opener reused the same bufnr (empty
          -- scratch case): there's no distinct prior buffer, and after
          -- the wipe below nvim will pick a fallback for the window.
          if have_prior_buf
            and vim.api.nvim_win_is_valid(win)
            and vim.api.nvim_buf_is_valid(buf_before)
          then
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
