# Punyo — Claude 向け作業ルール

## Xcode プロジェクトは xcodegen で生成される

`Punyo.xcodeproj/` は `.gitignore` されており、`project.yml` から `xcodegen generate` で毎回生成する。**pbxproj を手で編集してはいけない**（次回の generate で上書きされる）。

### いつ `xcodegen generate` を実行するか

以下を行った直後、**ビルドや実機/シミュレータ起動より前** に必ず走らせる:

1. `Punyo/` 配下にファイルを追加・削除・リネームしたとき
2. `project.yml` を編集したとき
3. `git checkout` / `git pull` / `git rebase` / `git merge` などで他ブランチの変更を取り込み、上記1・2に該当する変更が含まれていた可能性があるとき（迷ったら実行）

### 実行方法

```bash
cd <worktree>
xcodegen generate
```

### 失敗パターン

- リベース後にビルドして `cannot find type 'XXX' in scope` → 十中八九、新規ファイルが pbxproj に登録されていない。`xcodegen generate` を実行する
- pbxproj のコンフリクトを手で解消しようとしない。`git checkout --theirs Punyo.xcodeproj/project.pbxproj` などで一旦適当な側を採用し、その後 `xcodegen generate` で再生成する（そもそも pbxproj は追跡外なのでコンフリクトは起きないはずだが、過去に誤って追跡されたケースへの備え）

## ソース配置ルール

`project.yml` は `Punyo/` 全体を再帰的に取り込む設定なので、新規 Swift ファイルは `Punyo/<適切なサブディレクトリ>/` に置くだけで自動的にビルド対象になる（`xcodegen generate` 後）。個別に pbxproj へ登録する作業は不要。
