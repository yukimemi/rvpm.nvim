if vim.g.loaded_rvpm == 1 then
  return
end
vim.g.loaded_rvpm = 1

-- :Rvpm and :RvpmAddCursor are registered eagerly so they work without a
-- setup() call. Opt-in features (auto-generate autocmd) wait for setup().
require("rvpm.command").register()
