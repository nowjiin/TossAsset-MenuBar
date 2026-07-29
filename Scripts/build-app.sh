#!/bin/bash
# SwiftPM 실행 파일을 macOS .app 번들로 조립한다.
#
# Xcode 없이 Command Line Tools 만으로 동작한다.
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# SwiftPM 산출물 이름과 사용자에게 보이는 앱 이름은 다르다.
# 타깃명이 곧 Swift 모듈명이라 하이픈을 쓸 수 없기 때문이다 (`import TossAsset-MenuBarCore` 는 문법 오류).
# 번들 쪽 이름은 Info.plist 를 단일 출처로 삼는다. Scripts/package-release.sh 도 같은 값을 읽는다.
PRODUCT_NAME="TossAssetMenuBar"
INFO_PLIST="$ROOT/Resources/Info.plist"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INFO_PLIST")"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
APP_DIR="$ROOT/build/$APP_NAME.app"

cd "$ROOT"

echo "▸ 빌드 ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME"

BINARY="$(swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME" --show-bin-path)/$PRODUCT_NAME"
if [[ ! -x "$BINARY" ]]; then
	echo "실행 파일을 찾을 수 없습니다: $BINARY" >&2
	exit 1
fi

echo "▸ 번들 구성 ($APP_NAME.app)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
# CFBundleExecutable 과 실제 파일명이 일치해야 실행된다.
cp "$BINARY" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# 아이콘은 커밋된 산출물이다. 디자인을 바꿨으면 `swift Scripts/make-icon.swift` 로 다시 만든다.
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST" 2>/dev/null || true)"
if [[ -n "$ICON_NAME" ]]; then
	ICON_SOURCE="$ROOT/Resources/$ICON_NAME.icns"
	if [[ -f "$ICON_SOURCE" ]]; then
		cp "$ICON_SOURCE" "$APP_DIR/Contents/Resources/$ICON_NAME.icns"
	else
		# 조용히 넘기면 아이콘 없는 앱이 나오고 원인을 찾기 어렵다.
		echo "경고: $ICON_SOURCE 가 없어 아이콘 없이 빌드합니다." >&2
		echo "      swift Scripts/make-icon.swift 로 생성하세요." >&2
	fi
fi

# ad-hoc 서명(`-`)은 빌드마다 코드 서명 해시가 달라진다. Keychain 항목의 접근 권한이
# 서명 identity 에 묶여 있어서, macOS 가 재빌드된 앱을 매번 "다른 앱" 으로 보고 접근 허용을
# 다시 묻는다. CODESIGN_IDENTITY 로 고정 identity 를 주면 이 프롬프트가 사라진다.
#
#   CODESIGN_IDENTITY="TossAsset-MenuBar Dev" ./Scripts/build-app.sh
#
# 자체 서명 인증서 만들기: 키체인 접근 → 인증서 지원 → 인증서 생성 →
# 유형 "코드 서명", 자가 서명 루트. 만든 인증서 이름을 그대로 넘긴다.
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
	echo "▸ 서명 (ad-hoc — 재빌드마다 Keychain 접근을 다시 묻습니다)"
else
	echo "▸ 서명 ($SIGN_IDENTITY)"
fi
codesign --force --sign "$SIGN_IDENTITY" \
	--entitlements "$ROOT/Resources/$APP_NAME.entitlements" \
	--options runtime \
	"$APP_DIR"

echo "▸ 검증"
codesign --verify --verbose "$APP_DIR"

echo
echo "완료: $APP_DIR"
echo "실행: open \"$APP_DIR\""
