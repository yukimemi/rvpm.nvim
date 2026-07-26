-- Bootstrap for plenary-busted tests.
--
-- CI checks out plenary.nvim into `deps/plenary.nvim/`; local developers can
-- point at their own plenary install via $PLENARY or by placing plenary
-- under any of the fallback locations below.
--
-- `tests/plenary` is kept as a fallback for checkouts predating the move to
-- `deps/`: a vendored tree under `tests/` sits inside the directory the
-- kata-managed workflow walks when discovering `*_spec.lua`, so CI now
-- clones outside it.

local candidates = {
  "deps/plenary.nvim",
  "tests/plenary",
  vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/vendor/start/plenary.nvim",
  vim.fn.expand("~/.local/share/nvim/site/pack/vendor/start/plenary.nvim"),
}
if vim.env.PLENARY and vim.env.PLENARY ~= "" then
  -- Explicit override wins over the fallback chain.
  table.insert(candidates, 1, vim.env.PLENARY)
end

for _, path in ipairs(candidates) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.rtp:append(path)
    break
  end
end

-- Make rvpm.nvim itself importable.
vim.opt.rtp:prepend(vim.fn.getcwd())

vim.cmd("runtime plugin/plenary.vim")
vim.cmd("runtime plugin/rvpm.lua")
