# AGENTS.md

Guidance for AI agents (Claude / Codex / Gemini) working in this
repo. The yukimemi/* shared conventions live in the
`<!-- kata:agents:* -->` blocks below, sourced from
`yukimemi/pj-base` / `pj-nvim` via `kata apply` — see those for git
workflow, PR review cycle, test / lint commands, and renri's worktree
usage.

The sections above the marker blocks are rvpm.nvim-specific and
consumer-owned: edit them freely; `kata apply` won't touch them.

## コンセプト

- **Thin Lua wrapper**: `rvpm.nvim` は [`rvpm`](https://github.com/yukimemi/rvpm) CLI への薄い Lua レイヤー。ロジックは rvpm 本体に寄せ、Neovim 固有の配線 (user command、`BufWritePost` autocmd、floating terminal host、`:checkhealth`、log viewer) だけをこちらに置く。
- **Async by default**: 全てのサブプロセスは `vim.system` で非同期起動。UI スレッドを塞がない。補完の prewarm など少数の同期パスだけ `vim.system(...):wait(timeout_ms)` で境界付きブロック。
- **Convention over Configuration**: `plugin/rvpm.lua` が `:Rvpm` / `:RvpmAddCursor` を eager 登録するので、`setup()` 呼び出し無しでも最低限動く。`setup()` は `auto_generate` 等の opt-in 機能のためだけ。
- **Notify ゲート**: 全ての `vim.notify` 呼び出しは `cfg.options.notify` を経由する契約。`notify = false` で真に黙る (background chezmoi / generate 失敗警告も含めて)。Success 系の冗長通知は `verbose = true` でさらに opt-in。
- **chezmoi: source-of-truth モデル**: chezmoi 有効時、source 側編集は `chezmoi apply` → target に反映 (plus `rvpm generate`)。target 側編集は `rvpm generate` のみ走らせ、source へは push-back しない (`re-add` のロス — テンプレート消失 / 属性 prefix 喪失 — を避けるため)。詳細は `lua/rvpm/autocmd.lua` / `lua/rvpm/chezmoi.lua`。

## ローカル開発時の罠: 子 nvim で user init.lua が走る

一般的なテスト / lint コマンドは下の `kata:agents:nvim:*` ブロックにある。
ここに書くのは **このリポジトリ固有の落とし穴** で、CI では再現せずローカルだけで
起きる。

`PlenaryBustedFile` (= `plenary.test_harness.test_file`) は **子 nvim を spawn** するが、
`--noplugin -u tests/minimal_init.lua` を **子に渡さない**。これは `test_file` が
`test_paths(paths)` を opts 無しで呼ぶため (`opts.minimal` / `opts.minimal_init` が
nil なので minimal mode が OFF)。

結果として子 nvim はユーザの `~/.config/nvim/init.lua` を起動時に読み、

- ユーザが rvpm を使って rvpm.nvim 自身を依存に入れていると `~/.cache/rvpm/.../merged/`
  からこのリポジトリの **古いコピー** が rtp に乗り、`require("rvpm.autocmd")` が
  作業ツリーではなく merged キャッシュを返す
- → ローカルでテストが緑なのに作業ツリーの修正がそもそも走っていない、という
  silent な見落としが発生する

**CI** は user init が存在しないので無症状。kata-managed の `ci.yml` は今のままで動く。

**ローカルで spec を回すときは子 spawn を回避する.** outer プロセス内で
`plenary.busted` を直接 `run()` する:

```bash
# 単一 spec — 子 nvim を起こさず、tests/minimal_init.lua の rtp で実行
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.busted').run('tests/rvpm/autocmd_spec.lua')" \
  -c "qa!"

# 全 spec
set -e
status=0
for spec in tests/rvpm/*_spec.lua; do
  echo "=== $spec ==="
  nvim --headless --noplugin -u tests/minimal_init.lua \
    -c "lua require('plenary.busted').run('$spec')" -c "qa!" || status=$?
done
exit $status
```

nvim ブロックに載っている `PlenaryBustedFile` 形式は **CI 等のクリーンな環境** 専用と
読む。作業ツリーで rvpm.nvim を弄っているローカル機ではこちらの outer-process 形式を
使う。

plenary.nvim は `tests/minimal_init.lua` が以下の順に探す: `deps/plenary.nvim`
(CI がここに clone) → `tests/plenary` (旧レイアウト) →
`stdpath("data")` 配下の lazy / pack vendor。`$PLENARY` を設定すると先頭に
挿入されて最優先になる。

## 設計原則

**Resilience.** 背景ジョブの失敗 (chezmoi apply 非 0、`rvpm generate` 非 0、`rvpm doctor` warn 等) は `vim.notify` で WARN/ERROR 通知するが、Neovim の動作を止めない。autocmd は常に callback を消化して次の save を受け付けられる状態を保つ。chezmoi source-root の prewarm は fire-and-forget で、起動直後の 1 回目の save は source 判定 skip でも動くようフォールバックされている。

**Notify / verbose のゲート契約.** `lua/rvpm/chezmoi.lua` の `notify_if_enabled` / `notify_if_verbose`、`lua/rvpm/cli.lua` の `run()` など、UI に出る全 `vim.notify` は `cfg.options.notify` を必ず経由する。新規に `vim.notify` を書くときはこの pattern を踏襲する (直接呼ばない)。`verbose = true` は success/info 系の追加通知を解禁するもので、`notify = false` のときは無効 (notify が priority)。

**チェック前にテストを書く.** バグ修正や挙動変更は、可能な限り先に再現テストを `tests/rvpm/*_spec.lua` に書いてから実装する。plenary-busted の `describe` / `it` / `before_each` / `after_each` / luassert を使う。

**Windows 特性を忘れない.** CI には `windows-latest` があり、パス正規化 / case folding / pwsh の起動コスト / backslash vs forward slash で頻繁にコケる。`lua/rvpm/autocmd.lua` の `fold_case` / `relative_under`、`lua/rvpm/chezmoi.lua` の `to_os_path` はいずれも Windows 事故の再発防止のためのもの。パスを扱うコードを触るときは Windows 枝を意識する。

## アーキテクチャ

### ファイル構成

```text
plugin/
  rvpm.lua            — eager registration (`:Rvpm` / `:RvpmAddCursor`)。setup 不要で効く
lua/rvpm/
  init.lua            — `require("rvpm").setup()`、便利 Lua API (sync/generate/add/list/browse/log/doctor)
  config.lua          — defaults + `setup()` の tbl_deep_extend、`appname()` / `config_root()` / `config_toml()`
  cli.lua             — `run()` (async `vim.system`) と `run_sync()` (completion prewarm 用、タイムアウト付き)
  command.lua         — `:Rvpm` dispatcher、サブコマンド補完、plugin 名補完、`:RvpmAddCursor`
  terminal.lua        — float / split / tabnew / 任意 ex-command host で rvpm TUI を開く。exit 時に元バッファ復元 + safety gate
  autocmd.lua         — `BufWritePost` で `rvpm generate` を走らせる autocmd。chezmoi source 保存時は `chezmoi apply` を先行
  chezmoi.lua         — chezmoi 連携 (`enabled_in_config` / `prewarm_source_root` / `source_root` / `apply_source_to_target`)
  log.lua             — `rvpm log` を専用 `tabnew` バッファに展開、`BREAKING` 行を `DiagnosticError` でハイライト、`q` で wipeout
  health.lua          — `:checkhealth rvpm` — binary 存在 / config_root / config.toml / chezmoi 状態 / `rvpm doctor` 実行結果
tests/
  minimal_init.lua    — plenary を rtp に載せる bootstrap
  rvpm/*_spec.lua     — plenary-busted spec
deps/                 — CI が clone するテスト依存 (plenary.nvim)。gitignore 済み
.github/workflows/
  ci.yml              — kata-managed (yukimemi/pj-nvim)。ubuntu/macos/windows × stable/nightly + stylua lint
```

### 依存方向

- `plugin/rvpm.lua` → `command.lua` → `cli.lua` / `terminal.lua` / `log.lua`
- `init.lua.setup()` → `config.lua` → (opt-in) `autocmd.lua` → `chezmoi.lua`
- `health.lua` は `config.lua` / `chezmoi.lua` を参照
- `chezmoi.lua` は外部モジュールに依存しない (`require("rvpm.config")` のみ)

### :Rvpm dispatch (`lua/rvpm/command.lua`)

`SUBCOMMANDS` 配列に全サブコマンド名を持ち、`TUI` テーブルで「floating terminal に流すもの」を判定する:

- **Non-TUI** (`sync` / `generate` / `clean` / `doctor` / `init`): `cli.run()` で async 実行、notify で完了表示。
- **TUI** (`list` / `browse` / `config` / `edit` / `set` / `remove` / `update` / `add` / `tune` / `profile`): `terminal.open()` で host window に `rvpm <sub>` を jobstart (`term = true`)。exit 時に host を自動 teardown。
- **`log` だけ例外**: TUI ではなく `log.lua` の `render()` で専用 tabnew バッファに展開する。

`complete()` は 3 段階 (上から優先):
1. 1 個目の引数 — `SUBCOMMANDS` のプレフィックスフィルタ。
2. `PLUGIN_ARG_SUBS` (remove / update / edit / set / tune / log) の 2 個目の引数かつ `arg_lead` が `-` 始まりではない — `cfg.plugin_names()` (config.toml を読んで `[[plugins]]` を抜く) のプレフィックスフィルタ。
3. `arg_lead` が `-` 始まり、または空 (= `<Tab>` をベタ打ち) で 2 の plugin-name slot に該当しない — `FLAGS[sub]` (rvpm の各サブコマンド `--help` をハードコードしたミラー) のプレフィックスフィルタ。位置を問わない (`:Rvpm add foo/bar --on-<Tab>` や `:Rvpm sync <Tab>` で効く)。**rvpm 本体でフラグが増減したら `FLAGS` も更新すること** (フラグが取る *値* が増えただけなら据え置きでよい — `FLAGS` が保持しているのはフラグ名だけ)。

`:RvpmAddCursor` は `<cfile>` / `<cword>` から `owner/repo` 形式を正規表現で抜き、`rvpm add` に流す。`.git` サフィックスは strip。

### floating terminal host (`lua/rvpm/terminal.lua`)

`terminal.opener` オプションの値に応じて host window を準備してから `jobstart(cmd, { term = true })` で TUI を起動する。Opener の解釈:

| Value | 動作 |
|---|---|
| `"float"` *(default)* | `open_float()` で中央配置の floating window (width/height/border は設定通り) |
| `"split"` / `"hsplit"` | `:new` |
| `"vsplit"` | `:vnew` |
| `"tabnew"` / `"tab"` | `:tabnew` |
| 任意の文字列 | `vim.cmd(opener)` にそのまま流す (`"botright 20split"` / `"enew!"` 等) |
| `function()` | 直接呼ぶ。return 時に current window が使える状態であること |

**Safety gate.** `jobstart(term = true)` は current buffer を terminal に変換するので、opener 後も元バッファが current のままだと作業内容を潰す。`M._buffer_is_empty_scratch()` で「空の unnamed / unmodified scratch なら OK」と判定し、そうでなければ notify + abort する。`:enew!` でスクラッチ再利用する opener は許容、`:enew` (modified バッファに衝突) は明示 `!` 付きで通す設計。

Exit 時の復元:
- window が新規に作られていれば閉じる。
- window が再利用された場合は `buf_before` を window に戻す (スクラッチ再利用で `have_prior_buf == false` のときは nvim に任せる)。

### auto-generate autocmd (`lua/rvpm/autocmd.lua`)

`setup({ auto_generate = true })` (デフォルト) のとき `BufWritePost` を 1 つ登録する。

**分類 (`classify()`):**
- `config_root` 配下の `config.toml` / `before.lua` / `after.lua` / `plugins/<host>/<owner>/<repo>/(init|before|after).lua` → `"target"`
- chezmoi source root 配下の同パターン → `"source"`
- それ以外 → `nil` (skip)

**挙動:**
- `"target"`: `rvpm generate` のみ走らせる。chezmoi source への push-back はしない (`re-add` のロス回避)。target 編集を chezmoi 永続化したいなら source を直接編集する運用。
- `"source"`: `chezmoi apply --force <target>` で source 変更を target に materialize → 成功/失敗に関わらず `rvpm generate` を実行。

**Cache 挙動:**
- `chezmoi.prewarm_source_root()` は `register()` で fire-and-forget で起動。起動直後 1 回目の save は `source_root()` が `nil` を返す可能性があり、その場合 source 判定はスキップ (target 判定は config_root を直接見るので影響なし)。
- `config.toml` を保存すると `[options].chezmoi` が flip した可能性があるので `invalidate_cache()` + `prewarm_source_root()` を呼ぶ。今回 save の分類は保存前の cache を使うが、config.toml は config_root 配下なので `"target"` 判定で source_root を参照しない。

### chezmoi 連携 (`lua/rvpm/chezmoi.lua`)

Public API:
- `enabled_in_config()` — `config.toml` の `[options].chezmoi = true` を literal-boolean で判定 (Tera 展開はしない)。結果を cache。
- `prewarm_source_root()` — `chezmoi source-path <config_root>` を async 実行して resolved path を cache に入れる。chezmoi 無効 / 未インストール時は即 `false` (no subprocess)。in-flight ガードで重複 spawn を防ぐ。
- `source_root()` — cached path を返す。`nil` は「未 resolve or 無効」を意味し、autocmd 側は source 判定をスキップする signal として扱う。
- `apply_source_to_target(source, callback)` — `chezmoi target-path <source>` で target を計算し (`dot_` / `private_` 等の attribute rename を処理)、`chezmoi apply --force <target>` を走らせる。

**意図的に削除された機能:**
- `sync_target_to_source` (target → source への `chezmoi re-add` + `add` フォールバック) は削除済み (PR で refactor)。chezmoi の「source が source of truth」設計と衝突し、templated source を rendered output で上書きしたり、attribute prefix を失ったりするロスがあったため。target 編集を chezmoi に反映したい場合は `:Rvpm edit` / `chezmoi edit` 経由で source を編集する運用。

**Windows 対応:**
- `to_os_path()` で chezmoi subprocess に渡す path は backslash に変換する (chezmoi CLI の要求)。
- 内部比較は forward slash / case-folded (`fold_case`)。
- 返ってきた target-path はすでに OS-native なのでそのまま pass-through。

### health check (`lua/rvpm/health.lua`)

`:checkhealth rvpm` で以下を報告:
1. `rvpm` binary の PATH 存在
2. `config_root` ディレクトリの存在 (missing なら `rvpm init --write` を案内)
3. `config.toml` の存在
4. chezmoi 統合ステータス — `options.chezmoi` と `chezmoi` binary の両方揃っているか
5. `rvpm doctor` を 10 秒 timeout で実行し、exit code に応じて ok / warn / error、stdout を `info` で行単位表示

### 通知ゲート実装の pattern

```lua
-- lua/rvpm/chezmoi.lua
local function notify_if_enabled(msg, level)
  if require("rvpm.config").options.notify then
    vim.notify(msg, level, { title = "rvpm" })
  end
end

local function notify_if_verbose(msg, level)
  local opts = require("rvpm.config").options
  if opts.notify and opts.verbose then
    vim.notify(msg, level or vim.log.levels.INFO, { title = "rvpm" })
  end
end
```

- **失敗通知**: `notify_if_enabled` (`notify = true` なら必ず出す)。
- **成功/INFO 通知**: `notify_if_verbose` (`notify && verbose` のときだけ出す。デフォルト無音)。
- `notify = false` は両者とも silent にする priority 関係。

新規モジュールで `vim.notify` を直書きしない。必ずゲート関数経由。

## 参考: rvpm 本体との役割分担

- 設定ファイル解釈 (TOML parse / Tera 展開) / git / merge / loader.lua 生成 / TUI 実装 / chezmoi 書き込み — **全部 rvpm 本体**。
- Neovim 統合 (user command / autocmd / floating terminal host / :checkhealth / log viewer UI / BufWritePost での generate トリガー) — **rvpm.nvim**。
- chezmoi の「書き込みパス」は rvpm 本体が async + 2s timeout で制御 (`rvpm` の CLI subcommand 経由だと自動的に chezmoi-safe)。rvpm.nvim が chezmoi の **書き込み** を直接呼ぶのは、ユーザーが `:Rvpm edit` を経由せず Neovim から config/hook を直接保存した場合の source → target 反映 (`chezmoi apply`) のみ。**読み取り系** は別途 `chezmoi source-path` (source root 検出用の prewarm) と `chezmoi target-path` (attribute rename 解決) を呼ぶ — どちらも副作用なし。

<!-- kata:agents:base:begin -->
## Shared conventions

This file is the agent-agnostic source of truth (per the
[agents.md](https://agents.md) convention). The matching
`CLAUDE.md` and `GEMINI.md` files are thin shims that point back
here so each tool's auto-load behaviour still finds something.
**Edit AGENTS.md, not the shims.**

### Git workflow

- **No direct push to `main`.** Open a PR.
  - Exception: trivial typo / whitespace / docs wording fixes.
- Branch names: `feat/...`, `fix/...`, `chore/...`.
- **PR titles + bodies in English. Commit messages in English.**
- **Releases are PR-driven and tagging is automatic** — in repos that
  ship a release pipeline. Bump the version in the project's own
  manifest in a `chore/release-vX.Y.Z` PR; on merge to `main` the
  language layer's `auto-tag.yml` detects the bump, pushes the
  `vX.Y.Z` tag, and that tag is what fires `release.yml`. **Do not run
  `git tag` by hand** — the bot tag will collide and the manual push
  fails. The specifics belong to the layers shipping those two
  workflows, which are not the same layer: `kata:agents:rust:*` for
  which file holds the version and for `auto-tag.yml`,
  `kata:agents:rust-{cli,lib}:*` for what `release.yml` builds and
  publishes. A repo with no `auto-tag.yml` has no release pipeline at
  all: nothing tags, and the version field in its manifest may well
  be decoration.

### Pre-merge review

Review happens **before the pull request, on the operator's machine**,
via [magi](https://github.com/yukimemi/magi). This layer no longer
ships PR-side review bots: `claude-review.yml` and `claude.yml` were
removed from it. Their scope was
human-authored PRs — their own job-level `if:` already excluded
`chore/release-*`, `kata-apply/auto`, `apm-bump/auto` and
Renovate / Dependabot — which is exactly the set magi reviews, so
keeping them meant reviewing the same diff twice, a
`CLAUDE_CODE_OAUTH_TOKEN` secret per repository, Actions minutes on
private repos, and one trap that silently cost reviews: a PR editing
either workflow was skipped by `claude-code-action`'s
workflow-validation check and merged with a green check and no
review attached.

**"Removed" is a statement about this template layer, not about
every repo's current state.** Dropping a `[[file]]` entry stops kata
from managing the rendered file — it does not delete it. A repo that
had these workflows before this change keeps `claude-review.yml` /
`claude.yml` (and the `CLAUDE_CODE_OAUTH_TOKEN` secret) under
`.github/workflows/` until someone deletes them by hand, and until
then they still fire on every human-authored PR. Check
`.github/workflows/` before treating a PR as unreviewed-except-magi:
if either file is still there, its comments are a real review, not
noise to ignore.

- **`magi review <branch>`** runs only the review + verification +
  gate half of magi's graph: nothing competes, no implementation, no
  judging, no vote. That is the mode for hand-written work.
  `magi run "<task>"` is the full competition, for work handed over
  whole. Both end at the same gate.
- What the loop actually does: each reviewer gets its **own detached
  worktree pinned at the commit under review** (no reviewer can
  perturb the tree, and the fixer never races one); `verify.e2e` runs
  in the branch's worktree and its output is fed to the fixer;
  finding ids (`R2-1-3`) are assigned by magi, not by the agent, so
  the fixer's adoption report can be matched against them; the loop
  is bounded by `review_rounds`; `verify.gate` must exit 0 before any
  merge is attempted.
- **`magi.toml` is repo-owned, not kata-managed.** Point
  `verify.gate` at the exact command CI runs, so a local pass means a
  green PR, and point `verify.e2e` at the invocation that actually
  covers the repo — feature flags included. A gate that differs from
  CI turns a clean magi run into a red PR, which is the one failure
  this arrangement cannot absorb.
- **If you did not run magi, the change was not reviewed, and nothing
  will tell you.** Do not open a PR for a hand-written change before
  `magi review` comes back clean; if you must, say so in the PR body
  and say why. What does *not* count as a substitute: a green CI run
  (it compiles and tests, it does not review), and CodeRabbit's
  silence.
- **CodeRabbit stays installed and is not part of the gate.** It does
  not auto-review repositories under 10 stars — the common case here —
  so treat it as absent unless it posts. When it does post, its
  findings are a real review: address them, reply **in the inline
  thread** with an `@coderabbitai` mention (the review-comment
  *replies* endpoint,
  `gh api repos/<owner>/<repo>/pulls/<N>/comments/<id>/replies -f body=…`),
  and reply even when declining — say why, because a silent skip
  reads as overlooked. A "review limit reached" quota notice carries
  no findings and counts as quiet; re-trigger with
  `@coderabbitai review` when the quota refills if you want a real
  pass.
- **Read the report, not the exit status.** A reviewer seat that
  times out is logged as `WARN agent timed out seat=review-2` and
  then summarised as "raised 0 finding(s)" — indistinguishable from a
  genuinely clean pass in both the summary and `magi stats`. Check
  for timeouts before believing a clean round: a round where half the
  panel never answered is not a clean round.
- **Review artifacts stay local.** magi comments on a pull request
  only when it *stops* landing one. Findings, the fixer's adoption
  report and reviewer precision live in the run directory
  (`magi show`, `magi stats`). When the PR needs a record — a
  non-obvious fix, a finding declined with an argument — paste that
  part into the PR body or a comment yourself.
- With `merge = "pr"`, magi opens the pull request and keeps going:
  watches the checks, reads the review comments (human and bot), runs
  a bounded fix round when either is unhappy, pushes, and asks before
  merging. `land_approval` is on by default and **silence is a
  hold** — nothing merges unanswered. `magi answer` (or the web UI)
  is where it asks. Out of rounds leaves the PR open with a comment
  saying what still fails; `checks: unknown` never merges.
- **Merge gate**: magi's gate green — or CI green for a change magi
  never touched — **and** every review that did post resolved (a
  leftover `claude-review.yml`, CodeRabbit, a human) **and** the
  owner's explicit approval. The irreversible step stays a human
  decision.
- **No review-monitoring poll loop for bots this layer no longer
  ships.** The old loop existed to wait on them. Where a repo still
  has `claude-review.yml` (see above) the old cadence still applies
  until it is deleted; otherwise, after opening a PR wait for CI and
  report the wait state to the owner. When magi is landing the PR
  (`land = true`), magi does the watching.
- Bot-authored PRs (Renovate / Dependabot) need no review pass at
  all: CI green + owner approval.
- **Version-bump-only PRs** — a single `chore/release-vX.Y.Z` branch
  whose entire diff is `[workspace.package].version` /
  `[package].version` plus the matching inter-crate refs and the
  lockfile — likewise. There is nothing in a version bump for a
  reviewer to find, and the release pipeline downstream of merge
  (auto-tag → `release.yml`) is time-sensitive.

### Worktree workflow

> **Before your FIRST edit to any file, run `renri add` — NEVER edit the
> main checkout.** Read-only inspection (Read / Grep / Glob) stays on the
> main checkout; the instant you intend to *change* a file, you must
> already be in a worktree. The trap that keeps catching agents: diving
> into a fix the moment the diagnosis lands and editing in place. A
> concurrent agent shares the main checkout — your in-place edits will
> clobber theirs or be clobbered, and in a jj-colocated repo a stray
> working-copy commit entangles unrelated WIP into your branch. If you
> slip and edit in the main checkout, capture the diff first (jj already
> snapshotted it into the working-copy commit, so `jj diff > patch`; for
> git, `git stash` or save a patch — if you got as far as committing on a
> branch, just push it). Then reset the main checkout to pristine main
> (`jj new main@origin`, or `git switch -`), `renri add` a worktree, and
> re-apply the captured diff there.

Use [`renri`](https://github.com/yukimemi/renri) for any
commit-bound change. From the main checkout:

```sh
renri add <branch-name> --from main@origin            # create a worktree (jj-first), off latest upstream main
renri --vcs git add <branch-name> --from origin/main  # force a git worktree, off latest upstream main
renri remove <branch-name> -y --non-interactive  # cleanup after merge (agent-safe; see note)
renri prune                        # GC stale worktrees
```

Read-only inspection can stay on the main checkout.

**Always pass `--from <upstream main>`** (`main@origin` for jj,
`origin/main` for git). Without it, `renri add` forks off the *cwd
worktree's current HEAD* — in a long-lived main checkout that often
lags upstream, so the PR later shows up CONFLICTING against a `main`
that had already moved (e.g. a refactor merged upstream before the
branch was cut), forcing a manual re-port of the whole change.
`renri add` does fetch first, but fetching only updates `main@origin`
— it never moves the checkout's HEAD, so an explicit `--from` is what
guarantees a fresh base.

**Agents / non-interactive shells:** `renri remove` prints a details
panel and waits for a confirmation prompt — without `-y` it **hangs**,
and `--non-interactive` *alone* errors asking for `-y`. Always pass
`-y`, and add `--non-interactive` so a mistyped/omitted name fails
instead of opening a fuzzy picker (the same picker-fallback applies to
`remove` / `cd` / `exec` with no name). Use `-f`/`--force` to remove a
worktree that still has uncommitted changes or conflicts. To sweep
every merged-PR worktree in one shot: `renri remove --merged -y`.

### kata-managed sections

Several files in this repo are managed by `kata apply` from the
[`yukimemi/pj-presets`](https://github.com/yukimemi/pj-presets)
templates — the bytes between `<!-- kata:*:begin -->` and
`<!-- kata:*:end -->` markers, plus the overwrite-always files
listed in `.kata/applied.toml`. **Editing those bytes locally
won't survive the next `kata apply`** — push the change to the
upstream template repo (`yukimemi/pj-base` / `yukimemi/pj-rust` /
…) instead.

The marker scopes are layered, one per applied layer:
`kata:agents:base:*` is this section, and each layer adds its own
(`kata:agents:rust:*`, `kata:agents:rust-cli:*`,
`kata:agents:pnpm:*`, `kata:agents:firebase:*`, …). Which ones apply
*here* is a grep away: `<!-- kata:` in this file.

### This project's own conventions

Everything a layer ships is generic by construction: it describes the
stack the template assumed, not what this repo grew into. **Bytes
outside every marker pair are yours and survive `kata apply`** — so
project-specific conventions belong in a section of their own, outside
the markers (conventionally at the end of the file; if a later layer
appends its block below yours, no matter — kata only ever rewrites
between its own markers). Same mechanism as the `.gitignore` /
`.gitattributes` blocks.

Write those conventions down there rather than leaving them in one
agent's head, in commit archaeology, or in a README the agent will not
read. What earns a line:

- **Any layer default that does not hold here.** A layer states its
  assumption flatly ("Hosting is the primary target", "these rules are
  a placeholder to replace"). When the project has diverged, say so and
  say why — the layer's text keeps asserting the opposite on every
  apply, and an agent that only reads the blocks will act on it.
- **Facts duplicated across files with no compiler in between** — an
  address or a path that appears in code *and* in a rules/config file
  that cannot import it, a timeout that has to stay inside another
  timeout. List every copy, so the next edit finds them all.
- **kata-shipped files this project deleted on purpose**, together with
  the `once_applied = true` line in `.kata/applied.toml` that keeps
  them deleted. Otherwise someone helpfully restores one.
- **Shapes the runtime forces but no tool checks** — an export form a
  platform requires, import specifiers that must (or must not) carry a
  file extension, a directory whose contents are reachable by URL.
- **Invariants that money or access rest on**, naming the file and line
  that actually enforces them.
- **Which language the code speaks versus what a user reads**, when the
  two differ.

A repo whose `AGENTS.md` is nothing but kata blocks is a repo where
every agent re-derives all of that from scratch — and gets the layer
defaults wrong the same way each time.
<!-- kata:agents:base:end -->
<!-- kata:agents:nvim:begin -->
### Neovim plugin workflow

This repo follows the shared Neovim plugin conventions. The
language-agnostic conventions block above (`kata:agents:base:*`)
covers git workflow, PR review cycle, and worktree usage.

### Test / lint

There is no build step — Lua is interpreted, so the whole gate is
"tests pass and stylua is clean":

```sh
stylua --check .                    # format gate (what CI runs)
stylua .                            # apply formatting
```

Tests run through Neovim itself, one file per invocation. Which
framework is in play depends on `nvim.test_runner` in
`.kata/vars.toml`:

```sh
# test_runner = "mini"  (deps/mini.nvim)
nvim -u NONE -l scripts/run_tests.lua tests/<plugin>/test_foo.lua

# test_runner = "plenary"  (deps/plenary.nvim)
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/<plugin>/foo_spec.lua"
```

**Run one file per `nvim` invocation, and match CI's discovery
pattern.** CI enumerates specs with `find tests -type f -name …` and
loops in the shell rather than letting the framework walk the
directory: `PlenaryBustedDirectory` spawns `pwsh` on Windows runners
to enumerate files, and pwsh's ~5s startup blows plenary's internal
timeout. A file-at-a-time loop behaves identically on all three OSes
and keeps a crash in one spec from taking the rest of the suite with
it.

### Test dependencies live in `deps/`

CI clones the framework into `deps/mini.nvim` or `deps/plenary.nvim`.
Keep `deps/` out of the repo (it is in `.gitignore`) and out of
formatting (`.styluaignore`). If your `minimal_init.lua` hardcodes a
different path, fix the init file rather than the workflow — the
workflow is kata-managed and a local edit will be reverted.

### Neovim version support

CI runs the full matrix: `ubuntu` / `macos` / `windows` x `stable` /
`nightly`. A nightly-only failure is still a failure — either guard
the API behind a version check or fix the call. Don't reach for a
newer API without confirming it exists on `stable`; `vim.fn.has()` or
a `pcall` around the lookup is the usual guard.

### Lint / format policy

`.stylua.toml` is kata-managed (sourced from `yukimemi/pj-nvim`).
Edits to it in this repo won't survive the next `kata apply`; if a
setting is wrong, push the fix to `yukimemi/pj-nvim` so every Neovim
plugin using these templates picks it up. `.styluaignore` is
consumer-owned after the first apply — extend it freely.

### CI workflow

`.github/workflows/ci.yml` is kata-managed. The source lives in
`yukimemi/pj-nvim/.github/workflows/ci.yml.tera` (the `.tera` suffix
keeps GitHub Actions from running the source inside pj-nvim itself
and opts the file into kata's Tera rendering). Action versions are
pinned in `.kata/vars.toml` and bumped by Renovate, so don't edit
them inline in the workflow — the bump would be clobbered on the
next apply.

### Auto-merge preconditions (one-time, per repository)

Merging is GitHub's native auto-merge, armed by Renovate
(`platformAutomerge`) and by pj-base's `kata-apply` / `apm-bump`
workflows via `gh pr merge --auto`. Three repo-side settings are
required, and none of them can ship from a template — a freshly
created plugin has to be onboarded by hand, exactly like the pj-rust
and pj-denops lines:

* **`KATA_APPLY_TOKEN` secret** — a PAT with write access to the repo.
  `kata-apply.yml` / `apm-bump.yml` check out and push with it rather
  than `GITHUB_TOKEN`, whose pushes never trigger CI. Without it the
  job dies at checkout with `Input required and not supplied: token`.
* **`allow_auto_merge` enabled** on the repository.
* **Branch protection on `main`** requiring `test (ubuntu-latest /
  nvim stable)` and `stylua`. GitHub only arms auto-merge on a pull
  request that is currently blocked; with no required check the PR is
  immediately mergeable and the request is rejected with
  `Pull request is in clean status` or `Branch does not have required
  protected branch rules`.

Only the ubuntu legs are required on purpose. The macOS / Windows legs
and both nightly legs still run and still have to be read, but a flaky
runner or an upstream nightly regression must not wedge every
dependency PR.

```sh
gh secret set KATA_APPLY_TOKEN --repo yukimemi/<plugin>
gh repo edit yukimemi/<plugin> --enable-auto-merge
gh api -X PUT repos/yukimemi/<plugin>/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": {
    "strict": false,
    "contexts": ["test (ubuntu-latest / nvim stable)", "stylua"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
JSON
```

Skipping these is silent: the plugin looks fine, but `kata-apply`
fails every night and no template update ever reaches the repo.
<!-- kata:agents:nvim:end -->
