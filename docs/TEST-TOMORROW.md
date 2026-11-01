# v0.4 phone checks

The user's v0.3 tests passed recording, sound, Photos saving, offered HDR/ProRes profiles and basic controls. This pass targets the reported issues and new functions.

1. Rotate to both landscape directions before recording. Preview should be upright and fill the screen. Record a short take in each orientation and verify playback in Clips and Photos. The file orientation stays fixed during each take.
2. Confirm icons sit on the left in landscape and at the bottom in portrait. Scroll the rail for additional icons. Open Exposure/WB/Focus/Zoom: a small panel should leave the live image visible. Change a setting and watch its effect, including during a recording.
3. Toggle Look on/off while panning slowly. The creative preview should stay current, without growing delay. Try all presets. It is capped at 30 display fps even if recording at 60/120, and is not a color-managed HDR reference.
4. Open Format → FPS. Test 24, 30 and 60 if offered. Confirm the Info line and JSON match the selected rate. Verify actual frame rate externally from the original MOV. Format/rate changes are disabled during recording.
5. Open Clips. Play a clip with sound; save/share it. Check sizes and free space. Delete only a disposable clip after confirming the prompt; ensure its MOV and JSON vanish from Files and that Photos copies remain.
6. Open Connection and allow Local Network access. Connect and choose an actual Film Engine project. From Clips, send a short disposable take. Confirm its MOV and JSON appear in that project's Clips folder and its asset is listed in Film Engine. Local originals should remain.
7. Send the same clip again to the same project. It should not create a duplicate asset or overwrite unrelated files. Try with the Mac unavailable: the phone should report failure, retain its local clip, and allow a retry later.
8. Enable automatic sending, record two short takes in succession, and confirm each reaches the chosen project. Keep the app open during transfers. Disable automatic sending and confirm subsequent takes remain local.
9. Enter a distinctive scene/shot/take and notes in Slate. Record twice; check each JSON contains its own slate, FPS/profile and look. No slate text should appear in the video itself.

Retrieve the untouched MOV from Files or Film Engine for codec/bit-depth verification in Resolve or ffprobe. Photos sharing may transcode a clip. Report profile, FPS, orientation, monitor state and the action immediately preceding any failure.

## v0.4.1 follow-up

- Confirm the Home Screen says FE Camera and shows the blue filmstrip icon.
- Check top-bar separation and centered portrait Record control.
- Choose each Guides aspect ratio; confirm the selected ratio persists and is saved in the next slate. The original MOV is not cropped.
- Record past one minute and confirm HH:MM:SS:frames rolls over properly.
- Retry the failed clips while keeping the phone app open. Watch percent, MB/s and time remaining; wait for the final MOV + JSON confirmation. If it fails, copy the exact error from Connection.
