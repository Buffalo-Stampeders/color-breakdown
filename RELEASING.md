# Releasing a new version

GitHub builds and publishes both apps. All you do is bump the version and
push a tag.

1. **Bump the version in both apps** (they must match):
   - `ColorBreakdown.swift` → `AppInfo.version`
   - `windows/color_breakdown.py` → `VERSION`

2. **Commit and push**, then **tag** with the same number plus a leading `v`:
   ```
   git commit -am "Version 1.3.0"
   git push
   git tag v1.3.0
   git push origin v1.3.0
   ```

3. The **Build apps** workflow (Actions tab) then, in about 3 minutes:
   - builds the Windows app with `build-windows.bat` and tests that
     `install.bat` / `uninstall.bat` work
   - builds the Mac app with `./build.sh --no-install`
   - checks the tag matches both version numbers (fails without publishing
     if not)
   - publishes a GitHub Release with `ColorBreakdown-windows.zip`,
     `ColorBreakdown.exe` and `ColorBreakdown-mac.zip`

The Download links in the README always point to the newest release, and
installed copies offer the update the next time they start.

## Version numbers

Use `major.minor.patch` (e.g. `1.3.0`). Versions are compared number by
number, so `1.10.0` is newer than `1.9.2`.

## Fixing a bad tag

If the workflow fails before publishing (e.g. the version check), delete the
tag, fix, and tag again:
```
git tag -d v1.3.0
git push origin :refs/tags/v1.3.0
```

## Update check and repo visibility

Both apps check `https://api.github.com/repos/Buffalo-Stampeders/color-breakdown/releases/latest`
without logging in. **This only works while the repo is public.** For a
private repo GitHub answers "not found", and the check silently does nothing.
The repo is set in `AppInfo.updateRepo` (Mac) and `UPDATE_REPO` (Windows); set
both to `""` to turn update checks off.
