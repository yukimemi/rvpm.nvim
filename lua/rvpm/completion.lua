local M = {}

local cli = require("rvpm.cli")

-- 各 shell に対応する Vim filetype。 `rvpm completion` の出力に色を付けるためだけ。
-- 不明な shell は `sh` にフォールバック (`elvish` は Vim builtin が無いので素の text)。
local FILETYPE = {
  bash = "bash",
  zsh = "zsh",
  fish = "fish",
  powershell = "ps1",
  elvish = "text",
}

local function render(shell, stdout)
  local lines = vim.split(stdout or "", "\n", { plain = true })

  vim.cmd("tabnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = FILETYPE[shell] or "sh"
  -- `:w <path>` でユーザがそのまま保存できるように modifiable は残しておく。
  -- (rvpm log とは別方針 — log は viewer、 completion は "持ち帰る" バッファ)
  vim.api.nvim_buf_set_name(buf, "rvpm://completion/" .. shell)

  vim.keymap.set("n", "q", "<cmd>bwipeout<cr>", { buffer = buf, silent = true })
end

---Run `rvpm completion <shell>` and open the script in a scratch buffer
---so the user can `:w <path>` it to the right location for their shell.
---For non-interactive use, run `rvpm completion <shell>` from a real shell
---and redirect — that's the canonical install path.
---@param shell string  bash / zsh / fish / powershell / elvish
function M.show(shell)
  if not shell or shell == "" then
    vim.notify(
      "Usage: :Rvpm completion <bash|zsh|fish|powershell|elvish>",
      vim.log.levels.WARN,
      { title = "rvpm" }
    )
    return
  end
  cli.run({ "completion", shell }, {
    silent = true,
    on_exit = function(result)
      if result.code ~= 0 then
        vim.notify(
          "rvpm completion failed\n" .. (result.stderr or ""),
          vim.log.levels.ERROR,
          { title = "rvpm" }
        )
        return
      end
      vim.schedule(function()
        render(shell, result.stdout or "")
      end)
    end,
  })
end

return M
