#!/usr/bin/env bash
# Build APK arm64, đưa lên GitHub Releases và in câu SQL cập nhật bảng app_versions.
# Dùng: scripts/release_android.sh "Ghi chú phiên bản"
# Cần: flutter, gh (đã đăng nhập), app/env.json, app/android/key.properties.
set -euo pipefail
cd "$(dirname "$0")/../app"

NOTES="${1:-}"
REPO="khoaminh-dev/vg_svthm"
VERSION_LINE=$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}')
NAME="${VERSION_LINE%%+*}"
BUILD="${VERSION_LINE##*+}"
TAG="android-b${BUILD}"
APK="build/app/outputs/flutter-apk/app-release.apk"
OUT="build/viegrand-${BUILD}.apk"

[ -f android/key.properties ] || { echo "Thiếu android/key.properties, APK sẽ ký bằng khoá debug. Dừng."; exit 1; }
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Đã có release $TAG. Hãy tăng số sau dấu + trong pubspec.yaml."; exit 1
fi

flutter build apk --release --target-platform android-arm64 --dart-define-from-file=env.json
cp "$APK" "$OUT"
SHA=$(sha256sum "$OUT" | awk '{print $1}')

gh release create "$TAG" "$OUT" --repo "$REPO" --title "Android ${NAME} (build ${BUILD})" \
  --notes "${NOTES:-Bản thử nghiệm Android ${NAME}}" --prerelease
URL="https://github.com/${REPO}/releases/download/${TAG}/viegrand-${BUILD}.apk"

cat <<SQL

Chạy câu này trong Supabase SQL editor để người test thấy bản mới:

update app_versions set
  latest_build = ${BUILD}, latest_name = '${NAME}',
  apk_url = '${URL}',
  apk_sha256 = '${SHA}',
  notes = '${NOTES//\'/\'\'}', updated_at = now()
where platform = 'android';
SQL
