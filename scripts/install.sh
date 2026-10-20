#!/bin/sh
# Installs Vault's `myvault` command from the latest release and starts its
# setup.
# Nothing needs building, and nothing needs sudo:
#
#   curl -fsSL https://raw.githubusercontent.com/Atharv-tw/vault-app/main/scripts/install.sh | sh
#
# Add the desktop app as well:
#
#   curl -fsSL https://raw.githubusercontent.com/Atharv-tw/vault-app/main/scripts/install.sh | sh -s -- --app
#
# Run it again to update. Your data (in ~/.local/share/myvault, or
# ~/.local/share/todo from before the rename) is never touched.
set -eu

REPO="Atharv-tw/vault-app"
# Where the release files come from; set MYVAULT_RELEASE to try a build of your own.
BASE="${MYVAULT_RELEASE:-${TODO_RELEASE:-https://github.com/$REPO/releases/latest/download}}"
LIB="$HOME/.local/lib"
BIN="$HOME/.local/bin"

with_app=0
run_setup=1
for arg in "$@"; do
  case "$arg" in
    --app) with_app=1 ;;
    --no-setup) run_setup=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 64 ;;
  esac
done

if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
  echo "The ready-made programs are for 64-bit Linux on Intel or AMD." >&2
  echo "On anything else, build from source: https://github.com/$REPO#build-from-source" >&2
  exit 1
fi
command -v curl >/dev/null || { echo "This needs curl." >&2; exit 1; }
command -v tar >/dev/null || { echo "This needs tar." >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Unpacks one release file to a folder, replacing what was there only once
# the new copy has arrived whole.
fetch() {
  echo "Downloading $1"
  curl -fsSL "$BASE/$1" -o "$tmp/$1" || { echo "Could not download $1 from $BASE" >&2; exit 1; }
  mkdir -p "$tmp/$2" "$LIB"
  tar -xzf "$tmp/$1" -C "$tmp/$2"
  rm -rf "${LIB:?}/$2"
  mv "$tmp/$2/bundle" "$LIB/$2"
}

fetch myvault-cli-linux-x64.tar.gz myvault
rm -rf "${LIB:?}/todo"
mkdir -p "$BIN"
for name in myvault todo; do
  printf '#!/bin/sh\nexec "$HOME/.local/lib/myvault/bin/myvault" "$@"\n' > "$BIN/$name"
  chmod +x "$BIN/$name"
done
echo "Installed the myvault command: $BIN/myvault (todo still works too)"
if command -v vault >/dev/null 2>&1; then
  echo "Note: \`vault\` on your PATH is another program (HashiCorp Vault); Vault's command is \`myvault\`."
fi

if [ "$with_app" = 1 ]; then
  fetch vault-app-linux-x64.tar.gz vault-app
  icons="$HOME/.local/share/icons/hicolor/scalable/apps"
  mkdir -p "$icons" "$HOME/.local/share/applications"
  cp "$LIB/vault-app/vault.svg" "$icons/dev.atharv.vault.svg"
  cat > "$HOME/.local/share/applications/dev.atharv.vault.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Vault
Comment=Your second brain: goals, days, diary and memory
Exec=$LIB/vault-app/vault
Icon=dev.atharv.vault
Categories=Utility;Office;
StartupWMClass=dev.atharv.vault
DESKTOP
  echo "Installed the desktop app: Vault, in the application grid"
fi

case ":$PATH:" in
  *":$BIN:"*) ;;
  *)
    echo
    echo "$BIN is not on your PATH yet. Add this line to ~/.bashrc or ~/.zshrc, then open a new terminal:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

# Piped from curl, this script is not connected to the keyboard; the setup is.
if [ "$run_setup" = 1 ] && [ -r /dev/tty ]; then
  echo
  "$BIN/myvault" init < /dev/tty
else
  echo
  echo "Next: myvault init"
fi
