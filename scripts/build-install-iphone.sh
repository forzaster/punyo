#!/usr/bin/env bash
#
# Punyo iPhone 実機ビルド & インストールスクリプト
#
# 使い方:
#   scripts/build-install-iphone.sh                       # 接続中の iPhone に自動選択
#   DEVICE_UDID=00008120-... scripts/build-install-iphone.sh
#   DEVELOPMENT_TEAM=ABCDE12345 scripts/build-install-iphone.sh
#   scripts/build-install-iphone.sh --launch              # インストール後にアプリを起動
#   scripts/build-install-iphone.sh --list-devices        # 接続デバイスを一覧
#
# 環境変数:
#   DEVICE_UDID        インストール先 iPhone の UDID (未指定なら自動検出)
#   DEVELOPMENT_TEAM   コード署名用の Apple Developer Team ID
#   CONFIGURATION      Debug (デフォルト) / Release
#   SCHEME             デフォルト: Punyo
#   BUILD_DIR          派生データ出力先 (デフォルト: build/iphone)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SCHEME="${SCHEME:-Punyo}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUILD_DIR="${BUILD_DIR:-build/iphone}"
BUNDLE_ID="com.punyo.app"

LAUNCH_AFTER_INSTALL=0
LIST_DEVICES_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --launch) LAUNCH_AFTER_INSTALL=1 ;;
    --list-devices) LIST_DEVICES_ONLY=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' が見つかりません。$2"
}

require_cmd xcodebuild "Xcode コマンドラインツールをインストールしてください"
require_cmd xcrun      "Xcode コマンドラインツールをインストールしてください"

list_devices() {
  log "接続中の iOS デバイス一覧"
  xcrun devicectl list devices 2>/dev/null || \
    xcrun xctrace list devices 2>&1 | grep -Ei 'iPhone|iPad' | grep -v Simulator || true
}

if [[ $LIST_DEVICES_ONLY -eq 1 ]]; then
  list_devices
  exit 0
fi

detect_device() {
  if [[ -n "${DEVICE_UDID:-}" ]]; then
    echo "$DEVICE_UDID"
    return
  fi

  local tmp udid=""
  tmp="$(mktemp)"
  if xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1; then
    udid="$(/usr/bin/python3 - "$tmp" <<'PY' 2>/dev/null || true
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for d in data.get('result', {}).get('devices', []):
    props = d.get('deviceProperties', {}) or {}
    platform = props.get('platformIdentifier') or ''
    if 'iphoneos' not in platform.lower():
        continue
    tunnel = (d.get('connectionProperties') or {}).get('tunnelState', '')
    if tunnel and tunnel.lower() not in ('connected', 'connecting', 'available'):
        continue
    print(d.get('identifier', ''))
    break
PY
)"
  fi
  rm -f "$tmp"

  if [[ -z "$udid" ]]; then
    udid="$(xcrun devicectl list devices 2>/dev/null \
      | grep -iE 'iPhone' \
      | grep -iE 'connected|available' \
      | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9a-f]{40}' \
      | head -n1 || true)"
  fi
  echo "$udid"
}

if command -v xcodegen >/dev/null 2>&1; then
  log "xcodegen generate を実行"
  xcodegen generate
else
  warn "xcodegen が見つかりません。project.yml から Punyo.xcodeproj を生成できません。brew install xcodegen 後に再実行してください"
fi

UDID="$(detect_device)"
if [[ -z "$UDID" ]]; then
  warn "接続中の iPhone が見つかりませんでした"
  list_devices
  die "DEVICE_UDID=<UDID> を指定するか iPhone を接続して再実行してください"
fi
log "デバイス UDID: $UDID"

log "xcodebuild で iOS 実機向けビルド (scheme=$SCHEME, config=$CONFIGURATION)"
XCB_ARGS=(
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "id=$UDID"
  -derivedDataPath "$BUILD_DIR"
  -allowProvisioningUpdates
  CODE_SIGN_STYLE=Automatic
)
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  XCB_ARGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi
xcodebuild "${XCB_ARGS[@]}" build

APP_PATH="$(find "$BUILD_DIR/Build/Products" -type d -name '*.app' -not -path '*/PlugIns/*' 2>/dev/null | head -n1 || true)"
[[ -n "$APP_PATH" ]] || die ".app が見つかりませんでした ($BUILD_DIR/Build/Products)"
log ".app: $APP_PATH"

log "iPhone にインストール"
xcrun devicectl device install app --device "$UDID" "$APP_PATH"

if [[ $LAUNCH_AFTER_INSTALL -eq 1 ]]; then
  log "アプリを起動 ($BUNDLE_ID)"
  xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID"
fi

log "完了"
