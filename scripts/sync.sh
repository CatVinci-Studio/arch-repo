#!/usr/bin/env bash
# Brings the [catvinci] pacman repository in line with packages/*.json.
#
# Each packages/<pkgname>.json names one package build that an app's own
# release CI built and tested:
#   {"name": "levis-bin", "version": "0.8.13-1",
#    "url": "https://.../levis-bin-0.8.13-1-x86_64.pkg.tar.zst",
#    "sha256": "..."}
#
# For every request whose file is not in catvinci.db yet, this downloads
# the package, checks its sha256 and its pkgname, signs it, and adds it to
# the database. Files are served from the release tagged x86_64:
#   Server = https://github.com/CatVinci-Studio/arch-repo/releases/download/$arch
#
# Runs as root in an archlinux:base-devel container (.github/workflows/sync.yml).
# Needs GH_TOKEN, GH_REPO and ARCH_REPO_GPG_KEY.
set -euo pipefail

repo=catvinci
tag=x86_64
root="$(cd "$(dirname "$0")/.." && pwd)"

export GNUPGHOME="$(mktemp -d)"
printf '%s\n' "${ARCH_REPO_GPG_KEY:?ARCH_REPO_GPG_KEY is not set}" | gpg --batch --import
key="$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')"

work="$(mktemp -d)"
cd "$work"
gh release view "$tag" >/dev/null 2>&1 ||
  gh release create "$tag" --title "[catvinci] x86_64" \
    --notes "pacman repository files. See the README for how to use them."
gh release download "$tag" --pattern "$repo.db.tar.gz" --pattern "$repo.files.tar.gz" || true

# Package files the database lists now.
listed() {
  [ -f "$repo.db.tar.gz" ] || return 0
  bsdtar -xOf "$repo.db.tar.gz" '*/desc' | awk '/^%FILENAME%$/ { getline; print }'
}
current="$(listed)"

added=()
for request in "$root"/packages/*.json; do
  name="$(jq -r .name "$request")"
  url="$(jq -r .url "$request")"
  sha="$(jq -r .sha256 "$request")"
  file="${url##*/}"
  grep -qxF "$file" <<<"$current" && continue

  echo "Adding $file"
  curl -fsSL --retry 3 -o "$file" "$url"
  echo "$sha  $file" | sha256sum -c -
  # A request may only publish the package it is named after.
  pkgname="$(bsdtar -xOf "$file" .PKGINFO | awk -F' = ' '$1 == "pkgname" { print $2 }')"
  [ "$pkgname" = "$name" ] || {
    echo "$request asks for $name, but $file contains $pkgname" >&2
    exit 1
  }
  gpg --batch --yes --detach-sign --no-armor -u "$key" "$file"
  added+=("$file")
done

if [ "${#added[@]}" -eq 0 ]; then
  echo "catvinci.db is up to date"
else
  # repo-add replaces an older version of the same pkgname.
  repo-add --sign --key "$key" "$repo.db.tar.gz" "${added[@]}"
  # GitHub release assets cannot be symlinks, so .db and .files are copies.
  for name in db files; do
    rm -f "$repo.$name" "$repo.$name.sig"
    cp "$repo.$name.tar.gz" "$repo.$name"
    cp "$repo.$name.tar.gz.sig" "$repo.$name.sig"
  done
  cp "$root/catvinci.asc" .

  # Packages first, database last: the database never lists a file that is
  # not there yet.
  for file in "${added[@]}"; do
    gh release upload "$tag" "$file" "$file.sig" --clobber
  done
  gh release upload "$tag" --clobber catvinci.asc \
    "$repo".db "$repo".db.sig "$repo".db.tar.gz "$repo".db.tar.gz.sig \
    "$repo".files "$repo".files.sig "$repo".files.tar.gz "$repo".files.tar.gz.sig

  # Drop package files the database no longer lists.
  current="$(listed)"
  gh release view "$tag" --json assets --jq '.assets[].name' |
    grep -E '\.pkg\.tar\.zst(\.sig)?$' | while read -r asset; do
      grep -qxF "${asset%.sig}" <<<"$current" ||
        gh release delete-asset "$tag" "$asset" --yes
    done
fi

# Install path check: set up the repository with install.sh, the script
# users run, then download and verify every package as their pacman would.
pacman-key --init >/dev/null
for attempt in 1 2 3 4 5; do
  "$root/install.sh" && break
  sleep 10
done
pacman -Sw --noconfirm $(pacman -Slq "$repo")
pacman -Sl "$repo"
