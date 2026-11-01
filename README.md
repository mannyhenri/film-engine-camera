# Film Engine Camera · v0.3 field build

**Uncompiled source, untested on iPhone. No guarantee of ProRes/HDR support.**

New: manual ISO/shutter/focus/WB/zoom, experimental nondestructive Core Image monitoring, look recipes, slate metadata sidecar, composition guides and full field test checklist.

# Film Engine Camera · MVP 0.2 Alpha

Native iPhone camera prototype using SwiftUI and AVFoundation. Focus: real device capability negotiation for HDR / ProRes recording, and on-device inspection of saved footage.

## Supported *requested* recording profiles

- **HEVC 10-bit HLG (BT.2020)**: requires an HLG-compatible 10-bit sensor format and HEVC encoding.
- **ProRes 422 HQ HLG**: requires a supported 10-bit 4:2:2 sensor format, HLG color space, and ProRes 422 HQ encoding.
- **ProRes 422 HQ Apple Log**: requires a supported 10-bit 4:2:2 sensor format, Apple Log color space, and ProRes 422 HQ encoding.
- **HEVC SDR**: fallback when none of the above is supported.

Unsupported profiles are omitted from the picker. Nothing is silently downgraded. Apple Log 2 is **not** implemented yet. ProRes RAW is **not** implemented yet. This implementation uses `AVCaptureMovieFileOutput` rather than a custom sample-buffer/`AVAssetWriter` pipeline.

## Build on macOS

1. Install Xcode and XcodeGen (`brew install xcodegen`).
2. Run `xcodegen generate` in this directory.
3. Open `FilmEngineCamera.xcodeproj`, assign your Apple development team and unique bundle ID.
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

This build has **not been compiled or run on an iPhone** in this environment. It is an alpha implementation, not proven production recording. `AVCaptureMovieFileOutput` has platform/version-dependent HDR behavior. Apple Log preview can appear flat; monitor-grade LUTs/Metal grading are future work. Rotation, backgrounding, storage safeguards, locked exposure and full codec/bit-depth verification are not complete. For a guaranteed high-value shoot, use an established camera app until validated.

## Apple references

- [TN3104 ProRes recording](https://developer.apple.com/documentation/technotes/tn3104-recording-video-in-apple-prores)
- [Movie output available codecs](https://developer.apple.com/documentation/avfoundation/avcapturemoviefileoutput/availablevideocodectypes)
- [Capture color spaces](https://developer.apple.com/documentation/avfoundation/avcapturecolorspace)
