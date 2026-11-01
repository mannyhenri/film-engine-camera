# Film Engine Camera · v0.3.1 phone-test build

**iPhone SDK build verified with Xcode 26.1. Physical-device recording remains untested.**

New: manual ISO/shutter/focus/WB/zoom, experimental nondestructive Core Image monitoring, look recipes, slate metadata sidecar, composition guides and full field test checklist.

## Camera prototype

Native iPhone camera prototype using SwiftUI and AVFoundation. Focus: real device capability negotiation for HDR / ProRes recording, and on-device inspection of saved footage.

## Supported *requested* recording profiles

- **HEVC 10-bit HLG (BT.2020)**: requires an HLG-compatible 10-bit sensor format and HEVC encoding.
- **ProRes 422 HQ HLG**: requires a supported 10-bit 4:2:2 sensor format, HLG color space, and ProRes 422 HQ encoding.
- **ProRes 422 HQ Apple Log**: requires a supported 10-bit 4:2:2 sensor format, Apple Log color space, and ProRes 422 HQ encoding.
- **HEVC SDR**: fallback when none of the above is supported.

Unsupported profiles are omitted from the picker. Nothing is silently downgraded. Apple Log 2 is **not** implemented yet. ProRes RAW is **not** implemented yet. This implementation uses `AVCaptureMovieFileOutput` rather than a custom sample-buffer/`AVAssetWriter` pipeline.

## Build on macOS

1. Open the included `FilmEngineCamera.xcodeproj` in Xcode.
2. Sign in under Xcode → Settings → Accounts with access to the Gridlight development team. Automatic signing uses team `3AXRJ22S9P`; choose your own team if building independently.
3. Select the FilmEngineCamera target, confirm automatic signing, and select your connected iPhone. The app has its own bundle ID, `ai.gridlight.filmenginecamera`.

If editing `project.yml`, regenerate with XcodeGen (`brew install xcodegen`, then `xcodegen generate`). Keep the generated project committed.

4. Run on a real compatible iPhone (camera will not function in Simulator).
5. Review selected sensor dimensions/format and profile in the live overlay.
6. Record a short take; review **FILE** inspection text showing codec and color tags.
7. Tap **SAVE** to copy to Photos; original persists in the app Documents directory (visible under Files via the app's file-sharing settings).

## Validation needed on real hardware

- Check 10-bit **actual decoded pixel format / bit depth** externally with `ffprobe` or DaVinci Resolve. The app checks the chosen 10-bit sensor format and encoder capability, but codec + color tags alone do **not prove** an output is truly 10-bit.
- Verify HLG primaries `BT.2020` and transfer `HLG` in inspection and metadata tools.
- Check Apple Log transfer metadata and proper Resolve input color-space transform on a Pro model.
- Verify 24 fps, recording stability, temperature, free space, display orientation, sound sync and Photos export.
- Profile changes during capture are intentionally disabled.
- Save critical footage outside the app; deleting the app deletes its Documents.

## Known limitations

This build **compiles for iPhone**, but has not yet been installed or run on a physical device. The current Mac needs an Xcode account sign-in and an updated development provisioning profile before installation. It is an alpha implementation, not proven production recording. `AVCaptureMovieFileOutput` has platform/version-dependent HDR behavior. Apple Log preview can appear flat; monitor-grade LUTs/Metal grading are future work. Rotation, backgrounding, storage safeguards, locked exposure and full codec/bit-depth verification are not complete. For a guaranteed high-value shoot, use an established camera app until validated.

## Apple references

- [TN3104 ProRes recording](https://developer.apple.com/documentation/technotes/tn3104-recording-video-in-apple-prores)
- [Movie output available codecs](https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput/availablevideocodectypes)
- [Capture color spaces](https://developer.apple.com/documentation/avfoundation/avcapturecolorspace)

## Build verification — November 1, 2026

- Xcode 26.1, Debug, generic iOS device: build passed without Swift source warnings.
- Fixed Swift language mode, generated project, Photos permission, file sharing and version settings.
- Isolated capture hardware on its serial queue; UI state remains on the main actor.
- Debounced record taps, captured slate metadata before recording, restored the previous profile after failed configuration, and checked manual-control capabilities.
- Signed device build is pending Apple account/provisioning setup. HDR, ProRes, audio, Photos export and interruption handling still require the field tests below.

See [the phone checklist](docs/TEST-TOMORROW.md).
