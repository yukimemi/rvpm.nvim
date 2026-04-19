local M = {}

local cli = require("rvpm.cli")

local function render(stdout)
  local lines = vim.split(stdout or "", "\n", { plain = true })

  vim.cmd("tabnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "diff"
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "rvpm://log")

  local ns = vim.api.nvim_create_namespace("rvpm_log")
  for i, line in ipairs(lines) do
    if line:find("BREAKING", 1, true) then
      vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticError", i - 1, 0, -1)
    end
  end

  vim.keymap.set("n", "q", "<cmd>bwipeout<cr>", { buffer = buf, silent = true })
end

---Run `rvpm log` and show the output in a dedicated buffer.
---@param args? string[]
function M.show(args)
  args = args or {}
  local full_args = { "log" }
  vim.list_extend(full_args, args)
  cli.run(full_args, {
    silent = true,
    on_exit = function(result)
      if result.code ~= 0 then
        vim.notify(
          "rvpm log failed\n" .. (result.stderr or ""),
          vim.log.levels.ERROR,
          { title = "rvpm" }
        )
        return
      end
      render(result.stdout or "")
    end,
  })
end

return M
