# ぷにょ

実験アプリ。

## セットアップ

Xcode プロジェクト (`Punyo.xcodeproj/`) は [xcodegen](https://github.com/yonaskolb/XcodeGen) で `project.yml` から生成する方式。`.gitignore` されているのでリポジトリには入っていない。

初回:

```bash
brew install xcodegen
xcodegen generate
git config core.hooksPath .githooks   # ← 自動再生成を有効化（後述）
open Punyo.xcodeproj
```

`git config core.hooksPath .githooks` を一度実行しておくと、`.githooks/` にある `post-checkout` / `post-merge` / `post-rewrite` フックが有効になり、`git checkout` / `git pull` / `git rebase` の後に **`project.yml` か `Punyo/` に差分があれば** 自動で `xcodegen generate` が走る。この設定は clone や worktree ごとに1回必要（`.git/config` に書かれるため）。

## `xcodegen generate` を実行するタイミング

`project.yml` の `sources: - path: Punyo` により `Punyo/` 配下のファイルは自動収集される。ただし pbxproj は生成物なので、以下のタイミングでは **必ず再生成が必要**:

- `Punyo/` 配下のファイルを **追加・削除・リネーム** したとき
- `project.yml` を編集したとき
- `git pull` / `git checkout` / `git rebase` などで **上記の変更を含むコミットを取り込んだとき**
  - `core.hooksPath .githooks` を設定してあれば自動化されるが、フック未設定なら手動で

再生成しないと `cannot find type 'XXX' in scope` のようなコンパイルエラーが出る（ソースは存在するがプロジェクトが認識していない状態）。

## ビルド

```bash
xcodegen generate
xcodebuild -project Punyo.xcodeproj -scheme Punyo \
  -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator \
  -configuration Debug build
```
