#!/usr/bin/env bash
# Artisan Mobile - thiết lập dự án lần đầu (macOS / Linux)
set -e
cd "$(dirname "$0")"
flutter --version
flutter create --platforms=android,ios --org com.minhdang --project-name artisan_mobile .
M=android/app/src/main/AndroidManifest.xml
if ! grep -q android.permission.INTERNET "$M"; then
  python3 - "$M" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
s=re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>', s, count=1)
open(p,'w',encoding='utf-8').write(s)
PY
fi
P=ios/Runner/Info.plist
if [ -f "$P" ] && ! grep -q NSLocalNetworkUsageDescription "$P"; then
  /usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string 'Kết nối tới bộ điều khiển máy rang qua Modbus TCP trong mạng nội bộ.'" "$P" 2>/dev/null || \
  python3 - "$P" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
s=re.sub(r'</dict>\s*</plist>\s*$', '\t<key>NSLocalNetworkUsageDescription</key>\n\t<string>Kết nối tới bộ điều khiển máy rang qua Modbus TCP trong mạng nội bộ.</string>\n</dict>\n</plist>\n', s)
open(p,'w',encoding='utf-8').write(s)
PY
fi
flutter pub get
echo "XONG! Chạy: flutter run"
