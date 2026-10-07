# CatVinci Studio pacman repository

Signed Arch Linux packages for CatVinci Studio apps.

| Package     | App                                                     |
| ----------- | ------------------------------------------------------- |
| `levis-bin` | [Levis](https://github.com/CatVinci-Studio/Levis), AI-native WYSIWYG Markdown editor |

## Use

Run once. After that, `sudo pacman -Syu` keeps the packages up to date.

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/CatVinci-Studio/arch-repo/main/install.sh) levis-bin
```

[`install.sh`](install.sh) checks the signing key's fingerprint
(`B1B82E95327C63CCD15790F0B66D200DBA450FBC`), trusts it, adds `[catvinci]` to
`/etc/pacman.conf`, and installs the packages you name. Leave out the
package names to only set up the repository.

<details>
<summary>The same steps by hand</summary>

```sh
curl -fsSL https://raw.githubusercontent.com/CatVinci-Studio/arch-repo/main/catvinci.asc | sudo pacman-key --add -
sudo pacman-key --lsign-key B1B82E95327C63CCD15790F0B66D200DBA450FBC
printf '\n[catvinci]\nServer = https://github.com/CatVinci-Studio/arch-repo/releases/download/$arch\n' | sudo tee -a /etc/pacman.conf
sudo pacman -Syu levis-bin
```

</details>

## How it works

- The repository files are assets of the release tagged
  [`x86_64`](https://github.com/CatVinci-Studio/arch-repo/releases/tag/x86_64).
- Each app's release CI builds and tests its package, then pushes
  `packages/<pkgname>.json` (version, URL, sha256) here with a deploy key.
- `.github/workflows/sync.yml` then downloads the package, checks its sha256
  and its pkgname, signs it, updates `catvinci.db`, and downloads every
  package once more through pacman, after setting up with `install.sh`.

## Add an app

1. Build and test `<pkgname>-<version>-<rel>-x86_64.pkg.tar.zst` in the
   app's CI and attach it to the app's GitHub Release.
2. Add a deploy key with write access to this repository and store its
   private half as a secret in the app's repository.
3. After the app's release is published, have its CI commit
   `packages/<pkgname>.json`:

   ```json
   {
     "name": "<pkgname>",
     "version": "<version>-<rel>",
     "url": "https://github.com/<owner>/<app>/releases/download/<tag>/<file>",
     "sha256": "<sha256 of the file>"
   }
   ```

   Levis does this in the `update-arch-repo` job of its `release.yml`.

## Signing key

- Public key: `catvinci.asc`, fingerprint
  `B1B82E95327C63CCD15790F0B66D200DBA450FBC`.
- Private key: only the `ARCH_REPO_GPG_KEY` secret of this repository.

To replace it, store a new passphrase-less key in `ARCH_REPO_GPG_KEY`,
replace `catvinci.asc` and the fingerprint above and in `install.sh`, delete the `catvinci.db*`
and `catvinci.files*` assets, and run the Sync workflow. Users must then
repeat step 1.
