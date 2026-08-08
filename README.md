# ぷにょ

iOS 用「触って遊ぶ」実験アプリ。

## セットアップ

Xcode プロジェクト (`Punyo.xcodeproj/`) は [xcodegen](https://github.com/yonaskolb/XcodeGen) で `project.yml` から生成する方式。`.gitignore` されているのでリポジトリには入っていない。

初回:

```bash
brew install xcodegen
xcodegen generate
open Punyo.xcodeproj
```

## `xcodegen generate` を実行するタイミング

`project.yml` の `sources: - path: Punyo` により `Punyo/` 配下のファイルは自動収集される。ただし pbxproj は生成物なので、以下のタイミングでは **必ず再生成が必要**:

- `Punyo/` 配下のファイルを **追加・削除・リネーム** したとき
- `project.yml` を編集したとき
- `git pull` / `git checkout` / `git rebase` などで **上記の変更を含むコミットを取り込んだとき**
  - 特に他ブランチから移動した直後、ビルド前に `xcodegen generate` を挟むのを習慣に

再生成しないと `cannot find type 'XXX' in scope` のようなコンパイルエラーが出る（ソースは存在するがプロジェクトが認識していない状態）。

## ビルド

```bash
xcodegen generate
xcodebuild -project Punyo.xcodeproj -scheme Punyo \
  -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator \
  -configuration Debug build
```
