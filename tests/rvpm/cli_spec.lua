local cli = require("rvpm.cli")
local cfg = require("rvpm.config")

describe("rvpm.cli.run", function()
  local saved_system
  local saved_notify
  local last_call

  before_each(function()
    -- Capture vim.system invocations without actually spawning a child.
    -- The callback is intentionally NOT invoked here: detach=true with a
    -- real child would otherwise leak processes if the test died mid-run,
    -- and we are only verifying argument plumbing, not lifecycle.
    saved_system = vim.system
    last_call = nil
    vim.system = function(cmd, opts, _on_exit)
      last_call = { cmd = cmd, opts = opts }
      -- Return a stub matching `vim.SystemObj` enough to avoid runtime
      -- errors if a future code path inspects the handle. Tests never
      -- read these, but make the shape reasonable so a future caller
      -- that does is not silently broken.
      return {
        pid = 0,
        wait = function()
          return { code = 0, stdout = "", stderr = "" }
        end,
        kill = function() end,
      }
    end
    saved_notify = cfg.options.notify
    cfg.options.notify = false
  end)

  after_each(function()
    vim.system = saved_system
    cfg.options.notify = saved_notify
  end)

  it("does not pass detach by default (interactive `:Rvpm sync` keeps the child as a process-group child of Neovim)", function()
    cli.run({ "sync" })
    assert.is_not_nil(last_call, "vim.system must be called")
    assert.is_table(last_call.opts)
    assert.is_falsy(
      last_call.opts.detach,
      "default invocation must not detach — interactive `:Rvpm` callers rely on "
        .. "the completion callback firing to surface success/failure notify"
    )
  end)

  it("propagates detach=true so the child survives parent Neovim exit", function()
    -- Parent-exit survival is the whole point of the BufWritePost
    -- auto-generate path: a `:wq!` (or any editor crash mid-run) must
    -- not interrupt rvpm and leave a half-written loader.lua. cli.run
    -- exposes detach as a forward-only flag; once vim.system has
    -- received `{ detach = true }` libuv handles parent-exit survival
    -- (Linux: setsid; Windows: DETACHED_PROCESS).
    cli.run({ "generate" }, { detach = true })
    assert.is_not_nil(last_call)
    assert.is_true(
      last_call.opts.detach == true,
      "vim.system must receive { detach = true } verbatim so libuv treats "
        .. "the child as a session leader / detached process — anything else "
        .. "and the child dies with Neovim, breaking the issue-130 use case"
    )
  end)

  it("treats detach=false the same as omitted (does not enable detach via truthiness)", function()
    -- Belt-and-braces: if a caller writes `detach = false` explicitly we
    -- must not let some `or false` chain accidentally turn it back on.
    cli.run({ "list" }, { detach = false })
    assert.is_not_nil(last_call)
    assert.is_falsy(last_call.opts.detach)
  end)

  it("still passes text=true so stdout/stderr round-trip as strings", function()
    -- vim.system requires text=true for the callback's result.stdout to
    -- be a string instead of a byte buffer; the cli wrapper relies on
    -- this for the failure-notify branch (`result.stderr ~= ""`).
    cli.run({ "doctor" }, { detach = true })
    assert.is_true(last_call.opts.text == true)
  end)
end)
