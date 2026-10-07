#!/usr/bin/env bash
# Sets up the CatVinci Studio pacman repository [catvinci] and, optionally,
# installs packages from it:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/CatVinci-Studio/arch-repo/main/install.sh) levis-bin
#
# 1. Downloads the signing key and checks its fingerprint against the one
#    below before pacman trusts it.
# 2. Adds [catvinci] to /etc/pacman.conf, unless it is there already.
# 3. Runs `pacman -Syu <packages>` when packages are given.
#
# Safe to run again. Uses sudo when not run as root.
set -euo pipefail

fingerprint=B1B82E95327C63CCD15790F0B66D200DBA450FBC
key_url=https://raw.githubusercontent.com/CatVinci-Studio/arch-repo/main/catvinci.asc
server='https://github.com/CatVinci-Studio/arch-repo/releases/download/$arch'
conf=/etc/pacman.conf

sudo=""
[ "$(id -u)" -eq 0 ] || sudo=sudo
command -v pacman >/dev/null || {
  echo "pacman not found: this script is for Arch Linux and its derivatives." >&2
  exit 1
}

key="$(mktemp)"
trap 'rm -f "$key"' EXIT
curl -fsSL "$key_url" -o "$key"
got="$(gpg --with-colons --import-options show-only --import "$key" 2>/dev/null |
  awk -F: '/^fpr/ { print $10; exit }')"
[ "$got" = "$fingerprint" ] || {
  echo "Signing key fingerprint is $got, expected $fingerprint. Stopping." >&2
  exit 1
}
echo ":: Trusting the [catvinci] signing key $fingerprint"
$sudo pacman-key --add "$key" >/dev/null
$sudo pacman-key --lsign-key "$fingerprint" >/dev/null

if grep -q '^\[catvinci\]' "$conf"; then
  echo ":: [catvinci] is already in $conf"
else
  echo ":: Adding [catvinci] to $conf"
  printf '\n[catvinci]\nServer = %s\n' "$server" | $sudo tee -a "$conf" >/dev/null
fi

if [ "$#" -gt 0 ]; then
  $sudo pacman -Syu "$@"
else
  $sudo pacman -Sy
  echo ":: Done. Install packages with: sudo pacman -S levis-bin"
fi
