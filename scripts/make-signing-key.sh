#!/usr/bin/env bash
# Makes the key that Android releases are signed with, and hands it to GitHub
# as repository secrets so the release workflow can sign with it. Do this
# once, before the first release: every later release must be signed with the
# same key, or phones refuse to install it over the last one.
#
#   ./scripts/make-signing-key.sh            # key goes to ~/todo-release.jks
#   ./scripts/make-signing-key.sh PATH       # or somewhere else
#
# You choose the password. It is typed here, never shown, and never written
# into the repository.
set -euo pipefail
cd "$(dirname "$0")/.."

KEYSTORE="${1:-$HOME/todo-release.jks}"
ALIAS=todo

command -v keytool >/dev/null || { echo "This needs keytool, which comes with Java (sudo apt install openjdk-17-jdk)." >&2; exit 1; }
if [ -z "${DRY_RUN:-}" ]; then
  command -v gh >/dev/null || { echo "This needs the GitHub CLI, signed in (gh auth login)." >&2; exit 1; }
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi
if [ -e "$KEYSTORE" ]; then
  echo "$KEYSTORE already exists. A release key is made once; move it away first if you really want a new one." >&2
  exit 1
fi

read -rsp "Choose a password for the signing key (at least 6 characters): " TODO_KEY_PASSWORD; echo
read -rsp "Type it again: " again; echo
[ "$TODO_KEY_PASSWORD" = "$again" ] || { echo "Those did not match." >&2; exit 1; }
[ "${#TODO_KEY_PASSWORD}" -ge 6 ] || { echo "Too short." >&2; exit 1; }
export TODO_KEY_PASSWORD

# The password reaches keytool through the environment, so it never appears
# in the list of running commands.
keytool -genkeypair -keystore "$KEYSTORE" -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass:env TODO_KEY_PASSWORD -keypass:env TODO_KEY_PASSWORD \
  -dname "CN=CLI todo" >/dev/null
chmod 600 "$KEYSTORE"
echo "Made the key: $KEYSTORE"

if [ -n "${DRY_RUN:-}" ]; then
  echo "Dry run: nothing was sent to GitHub."
  exit 0
fi

base64 -w0 "$KEYSTORE" | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$REPO"
printf '%s' "$TODO_KEY_PASSWORD" | gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$REPO"
printf '%s' "$TODO_KEY_PASSWORD" | gh secret set ANDROID_KEY_PASSWORD --repo "$REPO"
printf '%s' "$ALIAS" | gh secret set ANDROID_KEY_ALIAS --repo "$REPO"

cat <<DONE

$REPO can now sign its releases.

Keep two things safe, somewhere other than this laptop as well:
  1. the file $KEYSTORE
  2. the password you just chose
If either is lost, nobody can update the app without uninstalling it first.

Builds made on this laptop (scripts/install-phone.sh) are still signed with
the laptop's own key, so your phone keeps updating from here as before. A
phone can only move between the two kinds by uninstalling the app.
DONE
