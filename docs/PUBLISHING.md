# Publishing checklist (maintainer notes)

## Push the repo

The repo is already initialised locally with `main` as the default branch and the author identity set.

```
git remote add origin https://github.com/<your-user>/Windows-Bluetooth-Fixer.git
git push -u origin main
```

Never put a token in the remote URL. Use `gh auth login` or the Git Credential Manager prompt.

## Make link previews show the banner

GitHub's link preview (Slack, Discord, X, Teams) uses the repository **Social preview** image, not the README.

1. Repo page > **Settings** > **General** > scroll to **Social preview** > **Edit** > **Upload an image**.
2. Upload `assets/banner.png` (1280x640, exactly the 2:1 ratio GitHub asks for).
3. Wait a minute; previews are cached by each platform.

## Cut a release

1. `launcher\build-launcher.ps1` rebuilds `BluetoothFixer.exe` if the launcher source changed.
2. Bump the version in `src\BluetoothFixer.psm1` (`$script:BFVersion`), `src\BluetoothFixer.Data.psd1` and `CHANGELOG.md`.
3. Zip the folder without `.git` and attach it to a GitHub Release as `Windows-Bluetooth-Fixer-<version>.zip`.
   Users download the release zip, extract, and double-click `BluetoothFixer.exe`.

## Regenerate the banner

```
powershell -ExecutionPolicy Bypass -File tools\make-banner.ps1
```

## Sanity pass before every push

- `git ls-files` shows no `.log`, `Reports/`, `Backups/`, `.env`, `*.zip`.
- README and docs contain no personal machine paths (`C:\Users\<name>`) or serial numbers.
- Screenshots in `assets/` show no serial numbers or MAC addresses.
