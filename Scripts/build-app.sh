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

# 소스의 Info.plist 는 버전을 올리지 않는다. 릴리스마다 커밋이 하나씩 붙고 그 커밋이 또
# 릴리스를 부르는 순환이 생기기 때문이다. 태그가 유일한 버전 출처다.
#
# 그래서 로컬 빌드는 그대로 두면 항상 0.1.0 이 되고, 업데이트 확인이 늘 "새 버전 있음" 을
# 띄운다. 여기서 git 정보로 채워 그 오탐을 없앤다.
#
# 비교용과 표시용을 나눈다:
#   CFBundleShortVersionString ← 최신 태그 (`0.3.0`). AppVersion 이 파싱해 릴리스와 비교한다.
#   CFBundleVersion            ← 빌드 식별 (`0.3.0+3`, `0.3.0+3.dirty`). 표시에만 쓴다.
# AppVersion 은 `+` 를 파싱하지 못하므로 short 쪽에 넣으면 버전이 통째로 깨진다.
#
# 릴리스 경로에서는 package-release.sh 가 두 값을 실제 릴리스 버전으로 덮어쓴다.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
	# 릴리스 태그는 CI 가 원격에 만든다. 로컬 클론에는 없어서, 그대로 두면 오래된 태그를 읽고
	# "새 버전 있음" 오탐이 그대로 남는다. 조용히 한 번 당겨온다 —
	# 오프라인이면 실패를 무시하고 로컬 태그로 진행한다 (빌드를 막을 이유가 없다).
	git -C "$ROOT" fetch --tags --quiet origin >/dev/null 2>&1 || true

	LATEST_TAG="$(git -C "$ROOT" tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | sed -n '1p')"
	if [[ -n "$LATEST_TAG" ]]; then
		TAG_VERSION="${LATEST_TAG#v}"
		AHEAD="$(git -C "$ROOT" rev-list --count "$LATEST_TAG..HEAD" 2>/dev/null || echo 0)"
		BUILD_ID="$TAG_VERSION"
		[[ "$AHEAD" != "0" ]] && BUILD_ID="$BUILD_ID+$AHEAD"
		git -C "$ROOT" diff --quiet HEAD 2>/dev/null || BUILD_ID="$BUILD_ID.dirty"

		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TAG_VERSION" "$APP_DIR/Contents/Info.plist"
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_ID" "$APP_DIR/Contents/Info.plist"
		echo "▸ 버전 $BUILD_ID"
	fi
fi

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
