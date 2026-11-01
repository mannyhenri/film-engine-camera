# Film Engine Camera 0.3 field test

## Build on macOS
1. `brew install xcodegen` (if needed)
2. `cd film-engine-camera && xcodegen generate`
3. Open `FilmEngineCamera.xcodeproj`, select Apple development team, connect iPhone and Run.
4. Grant Camera, Microphone and Photos permissions.

## Capture test matrix (repeat for each profile shown by device)
- Confirm app starts and sensor preview moves smoothly.
- Try HEVC HDR HLG and ProRes 422 HQ HLG/Apple Log when offered; **missing profile means device/format couldn't negotiate it**.
- Set ISO 100 and 1/48 shutter; adjust white balance and focus before recording.
- Record ten seconds and stop; inspect codec/primaries/transfer message.
- Save to Photos. Export file to Mac. Confirm codec, bit depth and HDR transfer in MediaInfo or DaVinci Resolve; tags alone do not prove bit depth.
- Switch Color Lab monitor on/off, test each look. Watch for stutter and thermal warnings. The ungraded master should not change.
- Enter project/scene/shot, record, then export both the MOV and JSON sidecar from Files > On My iPhone > Film Engine Camera (if displayed).
- Repeat after background/foreground and after screen rotation.

## Known limitations / no-go conditions
- No Xcode build or on-device verification has been completed in the development environment.
- 10-bit capture and color tags are configured/inspected, not yet independently verified from a physical device.
- Preview processing is experimental, computationally heavy, approximate, and not an HDR reference monitor; turn it off if unstable.
- Manual ISO range is UI-generic; AVFoundation clamps to active sensor's capabilities.
- No calibrated false color, waveform, zebra, focus peaking, raw pipeline, or reference-image overlay yet.
- ProRes RAW and Apple Log 2 negotiation are separate future work.
- The JSON sidecar is saved alongside the MOV in app Documents, **not** copied to Photos.
- Files visible in Photos may be transcoded by external sharing services: retrieve untouched MOV from Files when inspecting.
