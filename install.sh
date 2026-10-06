#!/bin/sh
set -eu

VERSION=1.13.2
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/wineprefixes/csp-ex-${VERSION}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wine-gecko-2.47.4"
GECKO_BASE=https://dl.winehq.org/wine/wine-gecko/2.47.4
X86_FILE=wine-gecko-2.47.4-x86.msi
X64_FILE=wine-gecko-2.47.4-x86_64.msi
X86_SHA256=26cecc47706b091908f7f814bddb074c61beb8063318e9efc5a7f789857793d6
X64_SHA256=e590b7d988a32d6aa4cf1d8aa3aa3d33766fdd4cf4c89c2dcc2095ecb28d066f

usage() {
    echo "Usage: $0 /path/to/CSP_1132w_setup.exe" >&2
    exit 2
}

[ "$#" -eq 1 ] || usage
INSTALLER=$1
[ -f "$INSTALLER" ] || { echo "Installer not found: $INSTALLER" >&2; exit 1; }

for command in wine wineboot winetricks curl sha256sum; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Required command not found: $command" >&2
        exit 1
    }
done

if [ -e "$PREFIX" ]; then
    echo "Prefix already exists: $PREFIX" >&2
    echo "Back it up and move it aside before running this installer again." >&2
    exit 1
fi

mkdir -p "$(dirname "$PREFIX")" "$CACHE"
export WINEPREFIX="$PREFIX"
export WINEDEBUG=-all
export WINEARCH=win64

printf 'Creating Wine prefix at %s\n' "$PREFIX"
wineboot -u

printf 'Configuring Windows 8.1 and required runtime/fonts...\n'
winetricks -q win81 vcrun2010 cjkfonts

fetch_gecko() {
    file=$1
    expected=$2
    target="$CACHE/$file"
    if [ ! -f "$target" ] || ! printf '%s  %s\n' "$expected" "$target" | sha256sum -c - >/dev/null 2>&1; then
        rm -f "$target"
        curl --fail --location --retry 3 --output "$target" "$GECKO_BASE/$file"
    fi
    printf '%s  %s\n' "$expected" "$target" | sha256sum -c -
}

fetch_gecko "$X86_FILE" "$X86_SHA256"
fetch_gecko "$X64_FILE" "$X64_SHA256"

printf 'Installing Wine Gecko...\n'
wine msiexec /i "$CACHE/$X86_FILE" /qn
wine msiexec /i "$CACHE/$X64_FILE" /qn

printf 'Starting the Clip Studio Paint installer. Complete its steps in the window.\n'
wine "$INSTALLER"
wineserver -w

PAINT_EXE=$(find "$PREFIX/drive_c/Program Files" -type f -name CLIPStudioPaint.exe -print -quit 2>/dev/null || true)
if [ -z "$PAINT_EXE" ]; then
    echo "Could not find CLIPStudioPaint.exe under Program Files in the prefix." >&2
    echo "The prefix is preserved at: $PREFIX" >&2
    exit 1
fi

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$BIN_DIR" "$APP_DIR"

cat > "$BIN_DIR/clip-studio-paint-ex" <<'LAUNCHER'
#!/bin/sh
set -eu
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/wineprefixes/csp-ex-1.13.2"
export WINEPREFIX="$PREFIX"
export WINEDEBUG="${WINEDEBUG:--all}"
command -v wine >/dev/null 2>&1 || { echo "wine is required" >&2; exit 1; }
PAINT_EXE=$(find "$PREFIX/drive_c/Program Files" -type f -name CLIPStudioPaint.exe -print -quit 2>/dev/null || true)
[ -n "$PAINT_EXE" ] || { echo "Clip Studio Paint was not found in $PREFIX" >&2; exit 1; }
exec wine "$PAINT_EXE" "$@"
LAUNCHER
chmod 755 "$BIN_DIR/clip-studio-paint-ex"

# Quote the executable path for the Desktop Entry Exec key.
EXEC_PATH=$(printf '%s' "$BIN_DIR/clip-studio-paint-ex" | sed 's/\\/\\\\/g; s/"/\\"/g')
cat > "$APP_DIR/clip-studio-paint-ex.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Clip Studio Paint EX
Comment=Launch Clip Studio Paint through Wine
Exec="$EXEC_PATH"
Terminal=false
Categories=Graphics;2DGraphics;
DESKTOP

printf '\nInstallation finished. Launch with: %s/clip-studio-paint-ex\n' "$BIN_DIR"
printf 'Wine prefix: %s\n' "$PREFIX"
printf 'If the desktop entry does not appear, log out and back in or launch from the command line.\n'
