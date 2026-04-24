local chezmoi = require("rvpm.chezmoi")
local cfg = require("rvpm.config")

describe("rvpm.chezmoi", function()
  local tmpdir
  local orig_config_toml

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    orig_config_toml = cfg.config_toml
    cfg.options.config_root = tmpdir
    cfg.config_toml = function()
      return tmpdir .. "/config.toml"
    end
    chezmoi.invalidate_cache()
  end)

  after_each(function()
    cfg.config_toml = orig_config_toml
    chezmoi.invalidate_cache()
    pcall(vim.fn.delete, tmpdir, "rf")
  end)

  local function write_config(body)
    local fd = assert(io.open(tmpdir .. "/config.toml", "w"))
    fd:write(body)
    fd:close()
    chezmoi.invalidate_cache()
  end

  describe("enabled_in_config", function()
    it("returns false when config.toml is missing", function()
      assert.is_false(chezmoi.enabled_in_config())
    end)

    it("returns true when [options].chezmoi = true", function()
      write_config("[options]\nchezmoi = true\n")
      assert.is_true(chezmoi.enabled_in_config())
    end)

    it("returns false when [options].chezmoi = false", function()
      write_config("[options]\nchezmoi = false\n")
      assert.is_false(chezmoi.enabled_in_config())
    end)

    it("returns false when the chezmoi key is absent", function()
      write_config("[options]\nconcurrency = 8\n")
      assert.is_false(chezmoi.enabled_in_config())
    end)

    it("ignores chezmoi keys in other sections", function()
      -- Only `[options].chezmoi` is authoritative; a stray `chezmoi = true`
      -- elsewhere must not flip the integration on.
      write_config("[vars]\nchezmoi = true\n\n[options]\nconcurrency = 8\n")
      assert.is_false(chezmoi.enabled_in_config())
    end)

    it("caches until invalidate_cache is called", function()
      write_config("[options]\nchezmoi = false\n")
      assert.is_false(chezmoi.enabled_in_config())
      -- Change the file on disk without invalidating — cached value wins.
      local fd = assert(io.open(tmpdir .. "/config.toml", "w"))
      fd:write("[options]\nchezmoi = true\n")
      fd:close()
      assert.is_false(chezmoi.enabled_in_config())
      -- After invalidation we see the updated value.
      chezmoi.invalidate_cache()
      assert.is_true(chezmoi.enabled_in_config())
    end)
  end)

  describe("source_root", function()
    it("returns nil when chezmoi is disabled", function()
      write_config("[options]\nchezmoi = false\n")
      assert.is_nil(chezmoi.source_root())
    end)
  end)

  describe("prewarm_source_root", function()
    it("is an immediate no-op when chezmoi is disabled (no subprocess)", function()
      write_config("[options]\nchezmoi = false\n")
      local start = vim.uv.hrtime()
      chezmoi.prewarm_source_root()
      local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      assert.is_true(
        elapsed_ms < 50,
        "prewarm should be instant when chezmoi is off, was " .. elapsed_ms .. "ms"
      )
      assert.is_nil(chezmoi.source_root())
    end)
  end)

  describe("apply_source_to_target", function()
    it("invokes the callback synchronously when chezmoi is disabled", function()
      write_config("[options]\nchezmoi = false\n")
      local called = false
      chezmoi.apply_source_to_target("/any/source/path", function()
        called = true
      end)
      assert.is_true(called, "callback must fire immediately when disabled")
    end)
  end)

  describe("notify option", function()
    -- Covers the regression where chezmoi.lua called vim.notify
    -- unconditionally, ignoring `setup({ notify = false })`. All chezmoi
    -- op failures must stay silent when the user turns notifications off.
    local notify_count
    local saved_notify

    before_each(function()
      notify_count = 0
      saved_notify = vim.notify
      vim.notify = function()
        notify_count = notify_count + 1
      end
      write_config("[options]\nchezmoi = false\n")
    end)

    after_each(function()
      vim.notify = saved_notify
    end)

    it("stays silent on apply_source_to_target when notify=false", function()
      cfg.options.notify = false
      local fired = false
      chezmoi.apply_source_to_target("/nonexistent/source", function()
        fired = true
      end)
      assert.is_true(fired)
      assert.equals(0, notify_count)
    end)
  end)

  describe("verbose option gating", function()
    -- Verbose controls whether *success* notifications fire; failures use
    -- the separate `notify` gate above. These tests exercise the disabled
    -- path (nothing happens) and the chezmoi-off early-return path
    -- (callback only, no notify). The enabled-success path needs a real
    -- chezmoi binary on PATH and is covered by manual smoke.

    local notify_count
    local saved_notify

    before_each(function()
      notify_count = 0
      saved_notify = vim.notify
      vim.notify = function()
        notify_count = notify_count + 1
      end
    end)

    after_each(function()
      vim.notify = saved_notify
    end)

    it("stays silent when verbose=false even if chezmoi would have succeeded", function()
      write_config("[options]\nchezmoi = false\n")
      cfg.options.notify = true
      cfg.options.verbose = false
      chezmoi.apply_source_to_target("/whatever", function() end)
      assert.equals(0, notify_count)
    end)

    it("stays silent when notify=false even if verbose=true", function()
      -- notify has priority: `notify=false` overrides `verbose=true`.
      write_config("[options]\nchezmoi = false\n")
      cfg.options.notify = false
      cfg.options.verbose = true
      chezmoi.apply_source_to_target("/whatever", function() end)
      assert.equals(0, notify_count)
    end)
  end)
end)
