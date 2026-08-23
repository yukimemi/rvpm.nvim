-- `lua/rvpm/command.lua` hardcodes a mirror of the rvpm CLI's flags so
-- `:Rvpm <sub> --<Tab>` completes without shelling out to `--help` on every
-- keystroke. That mirror drifts silently whenever rvpm core adds or renames a
-- flag — in Neovim a real flag simply never completes — so pin the flags we
-- depend on.
--
-- The module is loaded with `dofile` rather than `require` on purpose: `require`
-- resolves through the runtimepath, which on a developer machine with rvpm.nvim
-- *installed* finds the released copy (e.g. under
-- `~/.cache/rvpm/<appname>/plugins/merged`) before the working tree, so the
-- suite would assert against the wrong file and pass while this repo is broken.
local command = dofile(vim.fn.getcwd() .. "/lua/rvpm/command.lua")

describe("rvpm.command completion", function()
  -- (arg_lead, cmd_line) as Neovim passes them for `:Rvpm <line><Tab>`.
  local function complete(line)
    local arg_lead = line:match("%S+$") or ""
    if line:match("%s$") then
      arg_lead = ""
    end
    return command._complete(arg_lead, "Rvpm " .. line, #line + 5)
  end

  it("completes subcommands", function()
    local got = complete("")
    for _, sub in ipairs({ "sync", "add", "update", "self-update" }) do
      assert.is_true(vim.tbl_contains(got, sub), sub .. " must be completed")
    end
  end)

  it("completes add flags, including --setup", function()
    local got = complete("add --")
    -- `--setup` writes the entry's `setup` field in one line (rvpm >= 3.48.0).
    for _, flag in ipairs({ "--setup", "--on-cmd", "--rev", "--ai", "--no-lazy" }) do
      assert.is_true(vim.tbl_contains(got, flag), flag .. " must be completed")
    end
    assert.is_false(vim.tbl_contains(got, "--opts"), "--opts no longer exists")
  end)

  it("completes update flags", function()
    assert.is_true(vim.tbl_contains(complete("update --"), "--no-cooldown"))
  end)

  it("completes sync flags", function()
    local got = complete("sync --")
    for _, flag in ipairs({ "--prune", "--frozen", "--no-lock", "--rebuild" }) do
      assert.is_true(vim.tbl_contains(got, flag), flag .. " must be completed")
    end
  end)

  it("completes self-update flags", function()
    local got = complete("self-update --")
    for _, flag in ipairs({ "--yes", "--check" }) do
      assert.is_true(vim.tbl_contains(got, flag), flag .. " must be completed")
    end
  end)

  it("offers no flags for a subcommand that takes none", function()
    assert.same({}, complete("clean --"))
  end)
end)
