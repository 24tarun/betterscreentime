# How To Push Updates And New DMGs

This guide is for shipping a new BetterScreenTime release (example: `v1.1.1`) and uploading a fresh `.dmg` to GitHub Releases.

## 1. Sync Main

```bash
git checkout main
git pull --ff-only
```

## 2. Bump Version In Xcode

Before building:

- Set `MARKETING_VERSION = 1.1.1`
- Increment `CURRENT_PROJECT_VERSION` (build number), for example from `1` to `2`

## 3. Commit And Push Version Bump

```bash
git add .
git commit -m "Bump version to 1.1.1"
git push origin main
```

## 4. Build, Sign, Notarize, And Create DMG

From repo root:

```bash
./release-dmg.sh
```

This script does the full pipeline and regenerates:

- `release/BetterScreenTime.dmg`
- `release/export/BetterScreenTime.app`

## 5. Rename DMG For Release Asset

```bash
cp release/BetterScreenTime.dmg release/BetterScreenTime-v1.1.1.dmg
```

## 6. Create And Push Git Tag

```bash
git tag -a v1.1.1 -m "Release v1.1.1"
git push origin v1.1.1
```

## 7. Publish GitHub Release

On GitHub:

1. Go to **Releases**.
2. Click **Draft a new release**.
3. Select tag `v1.1.1`.
4. Title it `v1.1.1`.
5. Upload `release/BetterScreenTime-v1.1.1.dmg`.
6. Publish release.

## Notes

- If `create-dmg` is missing:

```bash
npm i -g create-dmg
```

- If the notary profile is missing, set up `AC_NOTARY`:

```bash
xcrun notarytool store-credentials "AC_NOTARY" --apple-id <email> --team-id <team-id> --password <app-specific-password>
```
