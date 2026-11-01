# FE Camera · v0.4.1

Native SwiftUI / AVFoundation iPhone camera. Clean HEVC SDR, 10-bit HEVC HLG, ProRes HQ HLG and Apple Log recording profiles are offered only when sensor and encoder negotiation succeed. Real recorded bit depth still requires external verification.

## Camera controls

- Portrait: scrollable icon rail at the bottom. Landscape: rail on the left.
- Tap an icon to open a small control panel; tap it again or × to close it. Preview remains visible.
- Exposure, white balance, focus and zoom can be adjusted during a take. Format and FPS changes are locked until recording stops.
- **Format → FPS** offers compatible sensor rates from 24, 25, 30, 48, 50, 60 and 120. Selecting a new profile starts at 24 fps. A configuration failure restores the previous profile/rate. These are normal-speed recordings at the selected FPS, not conformed slow motion.
- **Info** contains the detailed status, active format and latest saved-file inspection; the old permanent status card is gone.
- Preview follows interface orientation; each recording keeps the orientation present when Record was pressed. Do not rotate mid-take if you want a consistent composition.
- **Look** renders a downscaled creative monitor on a dedicated queue with GPU-backed Core Image. It caps presentation at 30 fps and drops stale frames instead of building a backlog. It is an SDR creative preview, not a calibrated HDR monitor. The recorded master is unfiltered.

## Slate

The slate stores project label, scene, shot, take, notes, selected FPS/profile and look recipe in a matching `.json` beside the MOV. It is not a visible clapboard, timecode overlay, or burn-in. Values are captured when recording starts; edits during a take apply to the next take. The take number increments after a successful recording. The upload destination is chosen separately in Connection.

## Clips and storage

Open the stacked-photos icon to see local clips, sizes and available storage. Each clip supports playback, saving to Photos, sharing, sending to Film Engine, and confirmed local deletion. Deletion removes the MOV, slate JSON and local upload receipt; it never deletes Photos or Film Engine copies. Files currently queued or transferring cannot be deleted. There is no automatic deletion.

## Optional Film Engine connection

The network icon opens Connection. Connect, choose a project, and optionally enable **Send new takes automatically**. Existing clips can be sent individually from Clips. Keep the app in the foreground during transfers; unsuccessful uploads retain the local original and can be retried. Transfers stream from disk rather than loading a ProRes file into phone memory. Retrying the same complete file is idempotent; interrupted partial transfers restart from the beginning.

The companion in `companion/bridge.py` runs on the Mac and talks to Film Engine's existing local HTTP API. It retrieves the project's storage report, places the original MOV and slate JSON in its video/Clips folder, and registers a `video_raw` asset. It does not create shots or change existing shot clips. Legacy projects use the video folder reported by Film Engine. Film Engine must be running.

The companion requires a random bearer pairing key. This is an authenticated local-network connection over HTTP, intended for a trusted Wi-Fi network; it is not a public internet upload service. Phone pairing settings can be supplied locally as `CAMERA_BRIDGE_URL` and `CAMERA_BRIDGE_TOKEN` build settings, or entered in Connection. Never commit pairing keys. `.local/` is ignored. User-entered pairing keys are stored in iOS Keychain.

For this Mac, the user approved starting `ai.gridlight.camera-bridge` at login. The service is in `~/Library/LaunchAgents/ai.gridlight.camera-bridge.plist`; configuration and logs are in `.local/`. The companion listens on port 5392, while the installed Film Engine app provides its API on loopback port 3100. If Film Engine uses a different port, update `engine_url` in the local config and restart the companion. Stop the service with `launchctl bootout gui/$(id -u)/ai.gridlight.camera-bridge`.

For a fresh setup, create a private JSON config containing `engine_url`, a random `token` of at least 24 characters, `host`, and `port`; run `python3 companion/bridge.py --config .local/bridge.json`. Python 3.11+ is required. `ffprobe` is recommended to measure uploaded clips and validate the movie before registration.

## Build and test

Open the committed `FilmEngineCamera.xcodeproj`. Development signing uses Emmanuel Henri team `W7QXFS7XBU`; choose your own team when building elsewhere. Use XcodeGen after editing `project.yml`. The bundle ID remains `ai.gridlight.filmenginecamera`, preserving existing phone recordings on updates. Wireless development installs are supported on the paired phone.

- iPhone and simulator builds verified with Xcode 26.1.
- Portrait and landscape layouts inspected in the simulator. Simulator has no rear camera; real orientation/monitor performance need phone testing.
- Companion tests: `python3 -m unittest discover -s companion -p 'test_*.py'`.
- Real project discovery verified against the installed Film Engine app; end-to-end user clip transfer is part of the phone checklist.

See [phone tests](docs/TEST-TOMORROW.md). Apple Log 2, ProRes RAW, scopes, focus peaking, zebras, calibrated HDR monitoring, background upload and clip editing remain outside this build.

## v0.4.1 refinements

The app uses Film Engine's blue folded-ribbon F icon, extracted from `electron/icon.icns` and the name FE Camera. The top bar has its own inset and spacing from the side controls; portrait controls are centered around Record. The counter shows elapsed non-drop-frame HH:MM:SS:frames from AVCaptureMovieFileOutput.recordedDuration (three frame digits at 120 fps). It is an elapsed recording display, not externally synchronized production timecode.

Guides supports 16:9, 1.85:1, 2:1, 2.39:1, 4:3, 1:1, 4:5 and 9:16. Selection persists and is captured in slate metadata. Guides do not crop the original recording.

Uploads display percentage, bytes sent, average MB/s and approximate remaining time. At 100% the UI waits for the Mac to verify and register the MOV before showing success. Upload size is sent explicitly. Interrupted uploads retain the original on the phone and can be retried; keep the app open during a transfer. iCloud synchronization of a project's folder is separate from the phone-to-Mac upload.

Verification: signed device and simulator builds pass; portrait and landscape spacing and ratio selection inspected in Simulator; 7 frame-timecode tests and 4 companion tests pass. A user-uploaded 1.03 GB / 13.5-second original was found and probed successfully in Blade Eternal's Clips folder: 4K, ProRes, 10-bit 4:2:2, 24 fps. Two later uploads failed (one HTTP 400 with no original reason logged; one phone-side connection reset). Explicit size headers and improved diagnostics are included; retry validation on the phone is still required.

Timecode regression check: `swiftc FilmEngineCamera/Camera/RecordingTimecode.swift tests/TimecodeTests.swift -o /tmp/fe-timecode-tests && /tmp/fe-timecode-tests`.

Clean View: tap the crossed-eye button to hide the side/bottom controls and open panels. The top bar, elapsed frame timecode and enabled framing/grid guides remain visible. Tap READY/REC in the top bar to start/stop; the eye restores controls. Toggling Clean View does not interrupt recording.
