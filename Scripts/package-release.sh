#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT/Resources/Info.plist"
REPOSITORY="${GITHUB_REPOSITORY:-nowjiin/TossAsset-MenuBar}"
SKIP_BUILD=0
VERSION_OVERRIDE=""

usage() {
	cat <<'EOF'
Usage: ./Scripts/package-release.sh [options]

Options:
  --repo OWNER/REPO  Repository used in the release download URL
  --version VERSION  Release version without changing the source Info.plist
  --skip-build       Package the existing build/*.app without rebuilding
  -h, --help         Show this help

EOF
}

fail() {
	echo "오류: $*" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--repo)
			[[ $# -ge 2 ]] || fail "--repo 값이 필요합니다."
			REPOSITORY="$2"
			shift 2
			;;
		--version)
			[[ $# -ge 2 ]] || fail "--version 값이 필요합니다."
			VERSION_OVERRIDE="${2#v}"
			shift 2
			;;
		--skip-build)
			SKIP_BUILD=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			fail "알 수 없는 옵션: $1"
			;;
	esac
done

[[ "$REPOSITORY" == */* ]] || fail "저장소는 OWNER/REPO 형식이어야 합니다."
[[ -f "$INFO_PLIST" ]] || fail "Info.plist를 찾을 수 없습니다."

APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INFO_PLIST")"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
VERSION="${VERSION_OVERRIDE:-$PLIST_VERSION}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "버전은 0.1.0 형식이어야 합니다."
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")"
SOURCE_APP_DIR="$ROOT/build/$APP_NAME.app"
DIST_DIR="$ROOT/dist/v$VERSION"
STAGING_DIR="$DIST_DIR/staging"
APP_DIR="$STAGING_DIR/$APP_NAME.app"
ARCHIVE_NAME="$APP_NAME.zip"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
ENTITLEMENTS="$ROOT/Resources/$APP_NAME.entitlements"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
	"$ROOT/Scripts/build-app.sh" release
fi

[[ -d "$SOURCE_APP_DIR" ]] || fail "앱 번들을 찾을 수 없습니다: $SOURCE_APP_DIR"
[[ -f "$ENTITLEMENTS" ]] || fail "entitlements를 찾을 수 없습니다: $ENTITLEMENTS"

mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$SOURCE_APP_DIR" "$APP_DIR"

# 자동 버전은 소스가 아니라 배포용 앱 복사본에만 반영한다.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_DIR/Contents/Info.plist"

echo "▸ ad-hoc 서명"
codesign --force --options runtime \
	--entitlements "$ENTITLEMENTS" \
	--sign - \
	"$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"

echo "▸ 릴리스 ZIP 생성"
ditto -c -k --keepParent "$APP_DIR" "$ARCHIVE_PATH"

(
	cd "$DIST_DIR"
	shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
)
ARCHS="$(lipo -archs "$APP_DIR/Contents/MacOS/$APP_NAME")"

rm -rf "$STAGING_DIR"

echo
echo "✓ 릴리스 패키지 생성 완료"
echo "  버전: v$VERSION"
echo "  macOS: $MINIMUM_MACOS 이상"
echo "  아키텍처: $ARCHS"
echo "  ZIP: $ARCHIVE_PATH"
echo "  SHA-256: $(awk '{ print $1 }' "$CHECKSUM_PATH")"
echo
echo "GitHub Release v${VERSION}에 다음 두 파일을 업로드하세요."
echo "  $ARCHIVE_NAME"
echo "  $ARCHIVE_NAME.sha256"
