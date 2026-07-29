#!/usr/bin/env bash
# Install Macaro: app + signed Siri shortcut for 80s80s Depeche Mode on available HomePods.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${HOME}/Applications"
BIN_DIR="${HOME}/bin"
SCRIPT="${SKILL_DIR}/scripts/depeche-mode-radio"
APPLET_SRC="$(mktemp -t macaro).applescript"
APP="${APP_DIR}/Macaro.app"

mkdir -p "$APP_DIR" "$BIN_DIR"

# CLI
ln -sfn "$SCRIPT" "${BIN_DIR}/depeche-mode-radio"
chmod +x "$SCRIPT" "${SKILL_DIR}/scripts/play-depeche-mode-homepods.applescript" 2>/dev/null || true

# Macaro.app
cat > "$APPLET_SRC" <<'EOF'
on run
	my playRadio()
end run

on open location theURL
	my playRadio()
end open location

on open theItems
	my playRadio()
end open

on playRadio()
	set radioCmd to (system attribute "HOME") & "/bin/depeche-mode-radio"
	try
		set resultText to do shell script radioCmd
		try
			display notification resultText with title "Macaro" subtitle "80s80s Depeche Mode"
		end try
		return resultText
	on error errMsg number errNum
		try
			display notification errMsg with title "Macaro" subtitle "Fehler"
		end try
		return "ERROR: " & errMsg
	end try
end playRadio
EOF

rm -rf "$APP"
osacompile -o "$APP" "$APPLET_SRC"
rm -f "$APPLET_SRC"

INFO="${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Macaro" "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Macaro" "$INFO" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Macaro" "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.merados.macaro" "$INFO" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.merados.macaro" "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleSpokenName Macaro" "$INFO" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleSpokenName string Macaro" "$INFO" 2>/dev/null || true

/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$INFO" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$INFO"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$INFO"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string com.merados.macaro" "$INFO"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$INFO"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string macaro" "$INFO"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" || true

# Sign + open shortcut for import (if not already present)
WFLOW="${SKILL_DIR}/shortcuts/Macaro.wflow"
OUT="${SKILL_DIR}/shortcuts/build/Macaro.shortcut"
mkdir -p "${SKILL_DIR}/shortcuts/build"
if [ -f "$WFLOW" ]; then
  shortcuts sign -m anyone -i "$WFLOW" -o "$OUT"
  if ! shortcuts list 2>/dev/null | grep -qx 'Macaro'; then
    open "$OUT"
    echo "→ Kurzbefehl 'Macaro' importieren (Add/Hinzufügen klicken)."
  else
    echo "→ Kurzbefehl 'Macaro' ist bereits vorhanden."
  fi
fi

echo "OK: Macaro.app + depeche-mode-radio"
echo "Siri:  Hey Siri, Macaro"
echo "Test:  open macaro://play   |   shortcuts run Macaro   |   depeche-mode-radio"
