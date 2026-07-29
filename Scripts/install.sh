#!/bin/bash
set -euo pipefail

APP_NAME="TossAsset-MenuBar"
DEFAULT_REPOSITORY="nowjiin/TossAsset-MenuBar"
REPOSITORY="${TOSS_ASSET_MENU_BAR_REPOSITORY:-$DEFAULT_REPOSITORY}"
VERSION="latest"
# 앱은 관례대로 /Applications 에 넣는다.
# 개인 Mac 은 보통 /Applications 가 admin 그룹 쓰기 가능이라 sudo 가 필요하지 않다.
# 관리 대상 Mac 처럼 권한이 없는 환경에서는 ~/Applications 로 물러난다.
SYSTEM_INSTALL_DIR="/Applications"
USER_INSTALL_DIR="$HOME/Applications"
INSTALL_DIR="${TOSS_ASSET_MENU_BAR_INSTALL_DIR:-}"
ARCHIVE_SOURCE=""
CHECKSUM_SOURCE=""
OPEN_AFTER_INSTALL=0

usage() {
	cat <<'EOF'
Usage: install.sh [options]

Options:
  --repo OWNER/REPO      GitHub repository (default: nowjiin/TossAsset-MenuBar)
  --version VERSION      Release version, with or without a leading v (default: latest)
  --install-dir PATH     Destination directory (default: /Applications, falls back to ~/Applications)
  --archive PATH_OR_URL  Use a specific archive (primarily for local verification)
  --checksum PATH_OR_URL Use a specific SHA-256 file
  --open                 Open the app after installation
  -h, --help             Show this help
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
			VERSION="$2"
			shift 2
			;;
		--install-dir)
			[[ $# -ge 2 ]] || fail "--install-dir 값이 필요합니다."
			INSTALL_DIR="$2"
			shift 2
			;;
		--archive)
			[[ $# -ge 2 ]] || fail "--archive 값이 필요합니다."
			ARCHIVE_SOURCE="$2"
			shift 2
			;;
		--checksum)
			[[ $# -ge 2 ]] || fail "--checksum 값이 필요합니다."
			CHECKSUM_SOURCE="$2"
			shift 2
			;;
		--open)
			OPEN_AFTER_INSTALL=1
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

# --install-dir 도 환경변수도 없으면 여기서 정한다.
if [[ -z "$INSTALL_DIR" ]]; then
	if [[ -w "$SYSTEM_INSTALL_DIR" ]]; then
		INSTALL_DIR="$SYSTEM_INSTALL_DIR"
	else
		INSTALL_DIR="$USER_INSTALL_DIR"
		echo "▸ $SYSTEM_INSTALL_DIR 에 쓸 권한이 없어 $INSTALL_DIR 에 설치합니다"
	fi
fi

[[ "$(uname -s)" == "Darwin" ]] || fail "이 앱은 macOS 14 이상에서만 실행됩니다."
[[ "$REPOSITORY" == */* ]] || fail "저장소는 OWNER/REPO 형식이어야 합니다."
command -v curl >/dev/null || fail "curl을 찾을 수 없습니다."
command -v ditto >/dev/null || fail "ditto를 찾을 수 없습니다."
command -v shasum >/dev/null || fail "shasum을 찾을 수 없습니다."
command -v codesign >/dev/null || fail "codesign을 찾을 수 없습니다."
command -v xattr >/dev/null || fail "xattr을 찾을 수 없습니다."

if [[ -z "$ARCHIVE_SOURCE" ]]; then
	if [[ "$VERSION" == "latest" ]]; then
		RELEASE_BASE="https://github.com/$REPOSITORY/releases/latest/download"
	else
		RELEASE_VERSION="${VERSION#v}"
		RELEASE_BASE="https://github.com/$REPOSITORY/releases/download/v$RELEASE_VERSION"
	fi
	ARCHIVE_SOURCE="$RELEASE_BASE/$APP_NAME.zip"
fi

if [[ -z "$CHECKSUM_SOURCE" ]]; then
	CHECKSUM_SOURCE="$ARCHIVE_SOURCE.sha256"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/toss-asset-menu-bar.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
ARCHIVE_PATH="$TEMP_DIR/$APP_NAME.zip"
CHECKSUM_PATH="$TEMP_DIR/$APP_NAME.zip.sha256"
EXTRACT_DIR="$TEMP_DIR/extracted"

fetch() {
	local source="$1"
	local destination="$2"

	if [[ "$source" == http://* || "$source" == https://* || "$source" == file://* ]]; then
		curl --fail --location --silent --show-error "$source" --output "$destination"
	else
		[[ -f "$source" ]] || fail "파일을 찾을 수 없습니다: $source"
		cp "$source" "$destination"
	fi
}

echo "▸ 다운로드: $ARCHIVE_SOURCE"
fetch "$ARCHIVE_SOURCE" "$ARCHIVE_PATH"
fetch "$CHECKSUM_SOURCE" "$CHECKSUM_PATH"

EXPECTED_SHA="$(awk 'NF { print $1; exit }' "$CHECKSUM_PATH" | tr '[:upper:]' '[:lower:]')"
[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]] || fail "올바른 SHA-256 값을 읽지 못했습니다."
ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{ print $1 }')"
[[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || fail "SHA-256 검증에 실패했습니다."
echo "▸ SHA-256 검증 완료"

mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_DIR"
SOURCE_APP="$EXTRACT_DIR/$APP_NAME.app"
[[ -d "$SOURCE_APP" ]] || fail "압축 파일에 $APP_NAME.app이 없습니다."
# Developer ID notarization 없이 배포하므로, 체크섬 확인을 마친 앱의 다운로드 격리를 제거한다.
xattr -dr com.apple.quarantine "$SOURCE_APP" 2>/dev/null || true
codesign --verify --deep --strict "$SOURCE_APP"

mkdir -p "$INSTALL_DIR"
TARGET_APP="$INSTALL_DIR/$APP_NAME.app"
BACKUP_APP="$TEMP_DIR/$APP_NAME.previous.app"

if [[ -e "$TARGET_APP" ]]; then
	echo "▸ 기존 앱 교체"
	mv "$TARGET_APP" "$BACKUP_APP"
fi

restore_previous_install() {
	rm -rf "$TARGET_APP"
	if [[ -e "$BACKUP_APP" ]]; then
		mv "$BACKUP_APP" "$TARGET_APP"
	fi
	fail "앱을 설치하지 못해 기존 앱을 복구했습니다."
}

if ! ditto "$SOURCE_APP" "$TARGET_APP"; then
	restore_previous_install
fi
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
if ! codesign --verify --deep --strict "$TARGET_APP"; then
	restore_previous_install
fi

echo "✓ 설치 완료: $TARGET_APP"

if [[ "$OPEN_AFTER_INSTALL" -eq 1 ]]; then
	open "$TARGET_APP"
fi
