# Fressh Android APK (Unofficial) — arm64 only

> **Not affiliated with the official Fressh project.**  
> Converts the official [EthanShoeDev/fressh](https://github.com/EthanShoeDev/fressh) **AAB** into a single **arm64-v8a release APK** for sideloading.

## Output

| File | Description |
|------|-------------|
| `fressh-arm64-v8a-release.apk` | One APK, **only arm64-v8a** native libs, release-style signed |

Most modern phones are arm64. This is smaller than a universal (all-ABI) APK.

## Download

1. Open **[Actions](https://github.com/ssyy6a/fressh-android-apk/actions)** → **Convert AAB to arm64 APK** → **Run workflow**
2. Or download from **[Releases](https://github.com/ssyy6a/fressh-android-apk/releases)** after a run finishes

Default source AAB:

```
https://github.com/EthanShoeDev/fressh/releases/download/%40fressh%2Fmobile%400.1.1/fressh-android.aab
```

## How it works

1. `bundletool build-apks --mode=universal` → intermediate single APK  
2. Unzip and **delete** `lib/armeabi-v7a`, `lib/x86`, `lib/x86_64`, … keep only `lib/arm64-v8a`  
3. `zipalign` + `apksigner` with a release keystore (generated or from secrets)

## Local build

Needs: Java 17+, Android **build-tools** (`zipalign`, `apksigner`), `curl`, `unzip`, `zip`.

```bash
chmod +x scripts/convert.sh
export ANDROID_HOME=~/Android/Sdk   # or your SDK path
./scripts/convert.sh
# → out/fressh-arm64-v8a-release.apk
```

Optional signing env:

```bash
export KEYSTORE_PATH=./my.keystore
export KEYSTORE_PASS=...
export KEY_ALIAS=...
export KEY_PASS=...
```

## Notes

- App content is the official release AAB; only packaging/ABI/signing change.
- Signing key is **not** Google Play’s key → install as unknown source; updates from Play won’t match this signature.
- 32-bit-only devices cannot install this APK.
- Prefer official Play closed test: https://fressh.dev/

## License

Scripts & workflow: MIT · Fressh app: MIT (upstream)
