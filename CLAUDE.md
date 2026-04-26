# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## コンセプト

- **Thin Lua wrapper**: `rvpm.nvim` は [`rvpm`](https://github.com/yukimemi/rvpm) CLI への薄い Lua レイヤー。ロジックは rvpm 本体に寄せ、Neovim 固有の配線 (user command、`BufWritePost` autocmd、floating terminal host、`:checkhealth`、log viewer) だけをこちらに置く。
- **Async by default**: 全てのサブプロセスは `vim.system` で非同期起動。UI スレッドを塞がない。補完の prewarm など少数の同期パスだけ `vim.system(...):wait(timeout_ms)` で境界付きブロック。
- **Convention over Configuration**: `plugin/rvpm.lua` が `:Rvpm` / `:RvpmAddCursor` を eager 登録するので、`setup()` 呼び出し無しでも最低限動く。`setup()` は `auto_generate` 等の opt-in 機能のためだけ。
- **Notify ゲート**: 全ての `vim.notify` 呼び出しは `cfg.options.notify` を経由する契約。`notify = false` で真に黙る (background chezmoi / generate 失敗警告も含めて)。Success 系の冗長通知は `verbose = true` でさらに opt-in。
- **chezmoi: source-of-truth モデル**: chezmoi 有効時、source 側編集は `chezmoi apply` → target に反映 (plus `rvpm generate`)。target 側編集は `rvpm generate` のみ走らせ、source へは push-back しない (`re-add` のロス — テンプレート消失 / 属性 prefix 喪失 — を避けるため)。詳細は `lua/rvpm/autocmd.lua` / `lua/rvpm/chezmoi.lua`。

## Git ワークフロー

- **main ブランチに直接 push しない。** 変更は必ずフィーチャーブランチを切り、Pull Request を作成する。
- ブランチ名は変更内容を端的に表す (例: `drop-chezmoi-readd-target-sync`, `fix-windows-path-classify`)。
- **PR のタイトル・本文・コミットメッセージは英語で書く。** Conventional Commits (`feat:` / `fix:` / `refactor:` / `test:` / `chore:`) を踏襲。scope は任意 (`fix(chezmoi): ...`)。

### PR レビューサイクル

- 全 PR で **Gemini Code Assist** と **CodeRabbit** がレビューを走らせる。両 bot の投稿を待ち、コメントに対処 (fix を PR branch に push) して、フィードバックが解消してからマージする。
- **fix を push したらレビュアーに返信する。** 対応した review comment のスレッドに、**@-mention (`@gemini-code-assist` / `@coderabbitai`)** 付きで reply する。silent な fix はレビュアーから見えず、盲目的に re-review されて監査トレイル (どの fix がどの指摘に応じたか) も失われる。
- **fix + reply を送ったらそこで止まらず、能動的に bot の再発言を監視する。** 数分おき (目安 5 分程度) に `gh pr view` / `gh api .../pulls/<n>/comments` を叩いて bot の返答を確認。新しい actionable コメントが来ていれば即 fix → @-mention → 監視再開、の loop を回す。Agent 環境なら `/loop` や `ScheduleWakeup` で自動化してよい。
- **スレッド settle の判定**: 1 つの review thread は、**最新の bot 返信が ack-only** ("Thank you" / "Understood" / "Acknowledged" / 新指摘なしの re-review サマリなど) になった時点で settle。`--diff` の再指摘や追加の actionable コメントが来たら未 settle に戻す。
- **監視ストップ条件**:
  1. **すべての open thread が settle** → その PR は quiet。ループを抜けてオーナーに merge 判断を仰ぐ。bot が素早く ack を返した場合、30 分待つ必要はない。
  2. **bot が返信を返さないまま最後の actionable コメントから 30 分経過** → timeout としてその thread を settle 扱いにする。bot が静かに諦めるケース (actionable を止めて何も返さないモード) を拾う fallback。短すぎ (<10 分) だと遅延投稿を取りこぼし、長すぎ (>1 時間) だと merge が無意味に遅れる。
- **Merge gating.** 以下の **両方** を満たすまで merge しない:
  1. レビュー bot (Gemini / CodeRabbit) が新しい actionable コメントを出さなくなった — fix → @-mention → 沈黙、のサイクルを回し続ける。
     Bot からの "Understood" / "Thank you" のような ack のみの返信はその thread の quiet pass とみなす。新しい actionable な指摘が来たら loop を再開。
  2. リポジトリオーナー (@yukimemi) が明示的に merge を承認している。
- **例外: bot-authored PR (Renovate, Dependabot).** Gemini と CodeRabbit はデフォルトでこれらを skip するので、"bot review を待つ" gate は適用しない。CI が green で owner 承認があれば merge OK。

## Development Commands

CI (`.github/workflows/ci.yml`) と揃えた実行パターン。Bash で全 OS 共通:

```bash
# 全 spec を逐次実行 (Windows の pwsh enumeration timeout 対策で per-spec ループ)
set -e
status=0
for spec in tests/rvpm/*_spec.lua; do
  echo "=== $spec ==="
  nvim --headless --noplugin -u tests/minimal_init.lua \
    -c "PlenaryBustedFile $spec" || status=$?
done
exit $status

# 単一 spec
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/rvpm/chezmoi_spec.lua"
```

plenary.nvim は以下のいずれかに置けば `tests/minimal_init.lua` が拾う:
- `tests/plenary/` (CI はここに checkout)
- `$PLENARY` 環境変数で明示指定
- `stdpath("data") .. "/lazy/plenary.nvim"` / pack vendor 配下

### ローカル開発時の罠: 子 nvim で user init.lua が走る

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

**CI** は user init が存在しないので無症状。CI は今のままで動く。

**ローカルで spec を回すときは子 spawn を回避する.** 以下のように outer プロセス
内で `plenary.busted` を直接 `run()` する:

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

`PlenaryBustedFile` を使う上の方の例は **CI 等のクリーンな環境** 専用と読む。
作業ツリーで rvpm.nvim を弄っているローカル機ではこちらの outer-process 形式を使う。

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
.github/workflows/
  ci.yml              — ubuntu/macos/windows × stable/nightly の 6 マトリクスで per-spec ループ実行
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
3. `arg_lead` が `-` 始まり、または空 (= `<Tab>` をベタ打ち) で 2 の plugin-name slot に該当しない — `FLAGS[sub]` (rvpm の各サブコマンド `--help` をハードコードしたミラー) のプレフィックスフィルタ。位置を問わない (`:Rvpm add foo/bar --on-<Tab>` や `:Rvpm sync <Tab>` で効く)。**rvpm 本体でフラグが増減したら `FLAGS` も更新すること**。

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

## CI (`.github/workflows/ci.yml`)

- マトリクス: `ubuntu-latest` / `macos-latest` / `windows-latest` × `nvim stable` / `nvim nightly` = 6 job。
- `rhysd/action-setup-vim` で nvim install、`actions/checkout` で plenary.nvim を `tests/plenary/` に clone。
- テスト実行は Bash で per-spec ループ (Windows の `PlenaryBustedDirectory` が pwsh 起動コストで 5s timeout に当たる事故を回避、全 OS 共通コードに統一)。
- status を累積して最後に exit — 途中で fail しても全 spec を走らせる。

## 参考: rvpm 本体との役割分担

- 設定ファイル解釈 (TOML parse / Tera 展開) / git / merge / loader.lua 生成 / TUI 実装 / chezmoi 書き込み — **全部 rvpm 本体**。
- Neovim 統合 (user command / autocmd / floating terminal host / :checkhealth / log viewer UI / BufWritePost での generate トリガー) — **rvpm.nvim**。
- chezmoi の「書き込みパス」は rvpm 本体が async + 2s timeout で制御 (`rvpm` の CLI subcommand 経由だと自動的に chezmoi-safe)。rvpm.nvim が chezmoi の **書き込み** を直接呼ぶのは、ユーザーが `:Rvpm edit` を経由せず Neovim から config/hook を直接保存した場合の source → target 反映 (`chezmoi apply`) のみ。**読み取り系** は別途 `chezmoi source-path` (source root 検出用の prewarm) と `chezmoi target-path` (attribute rename 解決) を呼ぶ — どちらも副作用なし。
