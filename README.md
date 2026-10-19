# Fressh Android APK (Unofficial)

> **Not affiliated with the official Fressh project.**  
> This repository only converts the official Android App Bundle (`.aab`) published by [EthanShoeDev/fressh](https://github.com/EthanShoeDev/fressh) into a single **universal APK** that can be sideloaded.

Official Fressh currently ships Android builds mainly as **AAB** (for Google Play closed testing). Many users prefer a direct `.apk` for sideloading. This repo automates that conversion with Google’s official `bundletool`.

## Download

Go to **[Releases](https://github.com/ssyy6a/fressh-android-apk/releases)** and download the latest `fressh-universal.apk`.

Or trigger the workflow yourself (see below).

## How it works

1. Download the official AAB from the Fressh release assets (default: `@fressh/mobile@0.1.1`).
2. Run Google `bundletool` with `--mode=universal` to produce one APK that contains all ABIs.
3. The resulting APK is signed with a **debug keystore** (fine for personal sideloading; not for Play Store).

Official source AAB example:

```
https://github.com/EthanShoeDev/fressh/releases/download/%40fressh%2Fmobile%400.1.1/fressh-android.aab
```

## Local conversion (Linux / macOS / WSL)

Requirements:
- Java 11+
- `curl` / `wget`
- `unzip`

```bash
chmod +x scripts/convert.sh
./scripts/convert.sh
# or point to a local .aab:
./scripts/convert.sh /path/to/fressh-android.aab
```

Output: `out/fressh-universal.apk`

## GitHub Actions

The workflow [`.github/workflows/convert-aab.yml`](.github/workflows/convert-aab.yml):

- Can be run manually (`workflow_dispatch`)
- Accepts optional AAB download URL
- Uploads the universal APK as a workflow artifact
- Optionally creates a GitHub Release with the APK attached

### Manual run

1. Open **Actions** → **Convert AAB to APK**
2. Click **Run workflow**
3. (Optional) paste a different AAB URL
4. Download the artifact or the Release asset

## Disclaimer

- This is an **unofficial** convenience packaging.
- The binary content comes from the official Fressh AAB; only the packaging format is changed.
- APK is signed with a debug key → Android will show “Unknown sources / debug signed”.
- Prefer the official Google Play closed test when possible: https://fressh.dev/
- MIT-licensed original project; this conversion tooling is also under MIT.

## License

- Conversion scripts & workflow: MIT
- Fressh application itself: MIT (see upstream)
