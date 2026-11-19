# Glow QA evidence

Date: 2026-11-07. Host: macOS 15 (Darwin 24.6), Swift 6.2.3, Command Line Tools only, no Xcode. No physical external monitor was attached.

## Results

| Check | Result |
| --- | --- |
| `swift package clean && swift build` | **Pass.** Clean build in 131 s, no warnings. |
| `./scripts/test.sh` | **Pass.** 62 tests, 0 failures. |
| Trailing whitespace in `Sources/`, `Tests/`, `docs/`, `scripts/` | None. |
| `swift run Glow --snapshot-ui <folder>` | **Pass.** It wrote 34 Settings and popover PNGs and 42 setup PNGs, light and dark. A sample of each was reopened and checked. |
| Real window on screen | **Pass**, on the test Mac on 2026-11-09, after the Glow Desk fix. See "In the app, on the test Mac" below. |
| VoiceOver, keyboard focus, ⌘W, coming to the front | Coming to the front: **Pass** on the test Mac, after the Glow Desk fix below. VoiceOver, keyboard focus and ⌘W: **Not done.** |
| `swift package clean` then `swift build --scratch-path .build-engine` (2026-11-08) | **Pass.** Clean build in 50 s, no warnings. |
| `./scripts/test.sh --scratch-path .build-engine` (2026-11-08) | **Pass.** 121 tests, 0 failures, no warnings. That's the 62 from before plus the hardware, key and migration tests, and the newer setup tests. |
| `scripts/bundle.sh` | **Pass.** `build/Glow.app`, universal (x86_64 arm64), 3.1 MB. `codesign -dv`: `Identifier=com.millerroberts.Glow`, `Signature=adhoc`, `flags=0x10002(adhoc,runtime)`. `codesign --verify --strict`: valid, satisfies its Designated Requirement. `LSUIElement` is true. The release binary has no debug flags in it. |
| Open at login (SMAppService) | **Registers**, on the test Mac on 2026-11-09: switching it on added the login item, and macOS said "Login Item Added". Opening at a real login wasn't tried. |
| Hardware: built-in display | **Pass** (see "Hardware pass" below). Native brightness: read, write, read-back and restore, to the exact level. Software dimming: set, read back, restored. |
| Hardware: external monitor (AOC 32G2WG3) | **Connected later; DDC/CI never answered.** It was unplugged for the first pass. Then, through an Anker hub, it was matched to its service, but every DDC/CI read on every profile failed after about 6 s, while EDID over the same path read in 1.5 ms. Later, brightness was sent without a reply on all three profiles while I watched, and nothing changed: the hub doesn't pass DDC/CI. See "AOC 32G2WG3 over DDC/CI" below. |
| DDC: `swift package clean` then `swift build --scratch-path .build-ddc` (2026-11-08) | **Pass.** Clean build in 43 s, no warnings. |
| DDC: `./scripts/test.sh --scratch-path .build-ddc` (2026-11-08) | **Pass.** 199 tests, 0 failures, no warnings. That includes 22 new hardware tests: 13 in `DDCDiscoveryTests.swift`, 6 in `DDCTransportTests.swift` and 3 in `CapabilityCatalogTests.swift`. |
| DDC: `--snapshot-ui` (2026-11-08) | **Pass.** `pane-connection-unlisted` (new) and `settings-connection-full`, now 4,000 pt tall so the LG section fits, light and dark. All were opened and looked at. |
| Brightness Match: `swift build --scratch-path .build-match` (2026-11-08) | **Pass**, no warnings. |
| Brightness Match: `./scripts/test.sh --scratch-path .build-match` (2026-11-08) | **Pass.** 199 tests, 0 failures. That includes the 28 in `BrightnessMatchTests.swift` and the 7 Brightness Match tests added to `BrightnessKeyTests.swift`. |
| Brightness Match: `--snapshot-ui` (2026-11-08) | **Pass.** 22 PNGs in `<folder>/match/`: the pane not matched, matched and out of date; the calibration intro, Quick compare, Guided point 2, Guided review, not enough displays, paused (intro and compare); and the grey patch. Light and dark. All were opened and looked at. |
| Brightness Match on this Mac's displays | **Not verified in the window.** `--probe-displays` (read only) shows the built-in display on native control at 68 % and the AOC 32G2WG3 on software dimming at 100 % (DDC didn't answer), so both qualify for matching. The calibration window and the grey patches weren't opened on them, because this pass didn't launch the GUI. |
| Scenes: `swift package clean` then `swift build --scratch-path .build-scenes` (2026-11-08) | **Pass**, no warnings. |
| Scenes: `./scripts/test.sh --scratch-path .build-scenes` (2026-11-08) | **Pass.** 200 tests, 0 failures, no warnings. That includes the 22 in the new `SceneTests.swift`. |
| Scenes: `--snapshot-ui` (2026-11-08) | **Pass.** New or changed: `pane-scenes-partial`, `pane-scenes-empty`, `scene-editor` (new scene), `scene-editor-saved`, `scene-editor-away`, `confirm-scene`, `popover`, `popover-no-scenes`, `popover-scene-applied`, `settings-displays-restore`, `settings-displays-restored`, `settings-controls` and `settings-general`, light and dark. All were opened and looked at. They turned up three bugs, now fixed (see "Scenes and the control audit" below). |
| Scenes on this Mac's displays (`--scene-selftest`) | **Pass**, 15 of 15 checks, through the real store and write pipeline. Only the built-in display's native brightness qualified (69 %, moved by 5 and back); the AOC is on software dimming, which the self-test leaves alone. The built-in's exact level, 0.6856319, was read back at the end. Run again on the final build. |
| Settings: `swift build --scratch-path .build-settings` (2026-11-08) | **Pass**, no warnings, after a full recompile of GlowApp. |
| Settings: `./scripts/test.sh --scratch-path .build-settings` (2026-11-08) | **Pass.** 209 tests, 0 failures, no warnings. That includes 6 new: 4 naming tests in `SceneTests.swift`, and the pane titles and the Glow pane's version line in `GlowAppTests.swift`. |
| Settings: `--snapshot-ui` (2026-11-08) | **Pass.** New: `settings-about` and `scene-editor-symbol` (a new scene after picking the moon, named "Night"). Changed: the sidebar in every Settings shot, `settings-displays-full` (Control mode choices, OSD menu triggers), `settings-controls`, `settings-scenes`, `settings-connection`, `scene-editor`, `scene-editor-saved`, `scene-editor-away`, `match/calibration-intro` and `setup/setup-5-done`, light and dark. All were opened and looked at. |
| Glow Desk: `swift package clean` then `swift build --scratch-path .build-popover` (2026-11-08) | **Pass**, no warnings. |
| Glow Desk: `./scripts/test.sh --scratch-path .build-popover` (2026-11-08) | **Pass.** 209 tests, 0 failures, no warnings. That includes the 3 in the new `StatusMenuTests.swift`. |
| Glow Desk: `--snapshot-ui` (2026-11-08) | **Pass.** Every popover shot, light and dark, at the new 308 pt width: `popover`, `popover-two`, `popover-two-matched`, `popover-one`, `popover-reading`, `popover-none`, `popover-paused`, `popover-no-scenes`, `popover-scene-applied`, and three new ones, `popover-many-scenes` (the **…** button), `popover-long-name` (a long name ends in an ellipsis) and `popover-keys-allow` (**Allow…**). All were opened and looked at. The right-click menu can't be drawn off screen; `StatusMenuTests` checks its items. |
| Integration, 2026-11-09: `swift build` | **Pass**, no warnings, with the keys, popover, setup and reading work merged. |
| Integration, 2026-11-09: `./scripts/test.sh` | **Pass.** 283 tests, 0 failures: the 209 from before, less the 29 old setup tests, plus 103 new. New files: `KeyHoldTests.swift` (12), `KeyWriteTests.swift` (12), `LevelBoxTests.swift` (15), `ReadingTests.swift` (31); `BrightnessKeyTests.swift` gained 6, and `SetupTests.swift` was rewritten (32). |
| Integration, 2026-11-09: `--snapshot-ui` | **Pass.** 178 PNGs. New folders `popover/`, `keys/` and `reading/`, and every setup step in `setup/`, light and dark. `popover/boxes-changed` (new at integration: the "Changed on the display" mark in Glow Desk), `reading/pane-reading`, `reading/pane-displays-changed`, `reading/pane-connection-reported`, `popover/settings-general-full`, `settings-reading` and `window-displays` were opened, and so was every shot each area added. |
| Integration, 2026-11-09: `--hold-selftest` | **Pass.** A tap 10 → 13 %, then a 2 s hold: 76 ticks of exactly 1 %, 19 → 95 %, largest gap between ticks 24 ms. The display got 17 writes and 4 read-backs, never more than one call in flight, and ended on the store's last value, confirmed. Demo displays behind a 120 ms adapter; no real display touched. |
| Integration, 2026-11-09: `--probe-readings` (read only) | **Pass.** Only the built-in display was attached. Discovery 31 ms; it rereads Brightness every 5 s while open (45 s in the background with Always); each pass answered in under 1 ms. Nothing written, no DDC/CI sent. DisplayServices answered 100 % (see "Built-in brightness reading" below). |
| Integration, 2026-11-09: `GLOW_ARCHS=arm64 scripts/bundle.sh` | **Pass.** `build/Glow.app`, arm64, 2.5 MB, no warnings. `Identifier=com.millerroberts.Glow`, `Signature=adhoc`, `flags=0x10002(adhoc,runtime)`; `codesign --verify --strict` valid. None of the debug flags is in the release binary. Launched from `build/Glow.app`. |
| Built-in display name, 2026-11-09 | **Pass.** The built-in display is named after the Mac, from the device tree's `product-name` without its size and year: `--probe-displays` prints `== MacBook Air (display 1, built-in)`, not "Built-in Retina Display". It falls back to "This Mac". `./scripts/test.sh`: 284 tests, 0 failures (new: `theBuiltInDisplayIsNamedAfterTheMac`). Rebundled and relaunched. The probe output quoted further down is from before the rename. |
| Trial and license keys, 2026-11-09 | **Pass.** 315 tests, 0 failures, with 31 new ones for a trial and license keys. Both were removed on 2026-11-16; see "Trial and license keys, 2026-11-09 to 2026-11-16" below. |
| Release tooling, 2026-11-09 | **Pass,** without an Apple account. <br>• `bash -n scripts/release.sh` is OK. <br>• `scripts/release.sh --unsigned` exits 0 and makes `dist/Glow-0.1.0-unsigned.dmg`, with its `.sha256` and `.dSYM.zip`. The checksum matches, the DMG holds Applications, EULA.txt and Glow.app, and the binary's UUID matches the dSYM's. <br>• With no `DEVELOPER_ID` or `NOTARY_PROFILE`, it refuses with one message. That message lists the missing variables, the five empty links and the development key, and nothing is built. <br>• Each other refusal was tried on a scratch copy: the key line, "prototype", the links and the version. <br>• The hardened runtime needs no entitlements (`docs/release.md`). <br>• Not verified: Developer ID signing, notarization and stapling; DDC/CI under the hardened runtime on a real monitor; the permission prompts on a signed build. |
| In the app, test Mac, 2026-11-09 | **Pass**, with a bug found and fixed: Glow Desk stayed open over Settings. See "In the app, on the test Mac" below. |
| Simulated monitors, 2026-11-09: `--simulated-selftest` | **Pass.** Four simulated DDC/CI monitors, found in 8.4 s, each on its expected profile. On each, brightness was raised by 5, read back, confirmed and restored, and each ended at its starting value. 0 requests rejected. See "Simulated DDC/CI monitors" below. |
| Simulated monitors in the app (test Mac), 2026-11-09 | **Pass.** A debug bundle run with `-GlowSimulatedMonitors all`: all four in Glow Desk and Settings on hardware control, a write to the slow AOC confirmed, and the profile ladder in Connection. |
| Final round, 2026-11-09: `./scripts/test.sh` | **Pass.** 337 tests, 0 failures: the 315 from before, plus `SimulatedMonitorTests.swift` (21) and one license test. |
| Final round, 2026-11-09: `GLOW_ARCHS=arm64 scripts/bundle.sh` | **Pass.** 2.7 MB, arm64, release. `strings` finds none of `GlowSimulatedMonitors`, `simulated-selftest`, `setup-ui` or "(simulated)" in the binary. With `GLOW_CONFIGURATION=debug` it's 5.7 MB and has them. |
| Displays already connected at launch, 2026-11-09 | **Fixed.** At launch the built-in display waited about 25 s for the AOC behind the hub. Now `--probe-readings` shows the built-in display ready at 21 ms, and the AOC on software dimming at 6.1 s after one request, not four. `./scripts/test.sh`: 344 tests, 0 failures (7 new). On the test Mac, Glow Desk showed three simulated monitors while the slow AOC said "Checking connection…", and Refresh Displays kept every row. See "Displays already connected at launch" below. |
| Trial and license keys removed, 2026-11-16 | **Pass.** `swift build`, no warnings. `./scripts/test.sh`: 314 tests, 0 failures: the 344 from before, less the 31 in the three removed files and one right-click menu test, plus 2 new. `--snapshot-ui` wrote 180 PNGs, with no `license/` folder; `window-displays` and `popover` were opened. `scripts/release.sh --unsigned` exits 0 and makes `dist/Glow-0.1.0-unsigned.dmg`. In the release binary, `strings` finds only `TrialRecord` and `LicenseKey`, the keys Glow deletes, and the License agreement link. See "Trial and license keys, 2026-11-09 to 2026-11-16" below. |
| Setup cut to what teaches, 2026-11-19: `swift build` | **Pass**, no warnings. |
| Setup cut to what teaches, 2026-11-19: `./scripts/test.sh` | **Pass.** 321 tests, 0 failures: the 315 on `main`, with `SetupTests.swift` at 38 (8 new, 4 rewritten, 2 deleted). |
| Setup cut to what teaches, 2026-11-19: `--snapshot-ui` | **Pass.** 198 PNGs, 52 of them in `setup/`, every step and state, light and dark. I opened every setup image. `scripts/readme-images.swift` changed only `docs/images/setup-light.png` and `setup-dark.png`; every Glow Desk and Settings image in `docs/images` came out byte-identical. See "Setup cut to what teaches, 2026-11-19" below. |

Earlier, `swift test` failed to import `Testing` on this toolchain. `scripts/test.sh` fixes that by passing the Command Line Tools framework paths. The earlier "blocked" result no longer applies.

## Hardware pass, 2026-11-08

Host: an Apple M4 MacBook. The built-in Liquid Retina display was the only display: the AOC 32G2WG3 was unplugged throughout, and the pass went ahead without it. Both commands come from the debug build in `.build-engine`.

`Glow --probe-displays` (read-only):

```
Glow display probe (read-only). DDC/CI interface: IOAVService calls found
Discovery took 15 ms and found 1 display(s).

== Built-in Retina Display (display 1, built-in)
   identity: vendor 0x610, product 0xA064, serial present
   transport: Internal
   framebuffer: IOService:/AppleARMPE/arm-io@10F00000/AppleH16GFamilyIO/disp0@8000000/IOMobileFramebufferShim
   matched: not matched to a DDC service (built-in displays don't speak DDC)
   note: Brightness through macOS’s own control (DisplayServices)
   note: Safe mode: reading only, until Glow is reopened
   settings:
   - Brightness: 31%; route Native control; evidence Tested successfully; access readWrite; editable
     Read through macOS’s own brightness control
   - Resolution: 3420 × 2214; route Native control; evidence Tested successfully; access readOnly
     CoreGraphics active mode
   - Refresh rate: 60 Hz; route Native control; evidence Tested successfully; access readOnly
     CoreGraphics active mode
   baseline (values read before any change): brightness 31
```

`Glow --ddc-selftest` (brightness only, through `DisplayWritePipeline`, the same path the app uses):

```
Glow brightness self-test. Each display: read, change by 5, confirm, restore, confirm.

== Built-in Retina Display (display 1)
   route: Native control; evidence: Tested successfully
   exact level before: 0.3125
   write: 31 → 36; read back 36 in 3 ms, confirmed
   restore: 36 → 31; read back 31 in 1 ms, confirmed
   final read: 31 (started at 31)
   exact level restored: accepted, read back 0.3125

== Software dimming on Built-in Retina Display
   before 100 %; set 80 % accepted, read back 80 %
   restore accepted, read back 100 %

Self-test passed.
```

A separate DisplayServices read afterwards gave 0.3125, the level before the test. An earlier run had restored only the whole percent (0.31). That was put back by hand to 0.3125 and confirmed, and the self-test now saves and restores the exact level.

**AOC 32G2WG3: no write → read-back → restore log.** It wasn't connected, so no DDC/CI command reached a real monitor in this pass. Nothing here claims it did.

### AOC 32G2WG3 over DDC/CI, later on 2026-11-08

The AOC was plugged in through an Anker USB-C hub on the same M4 MacBook. Everything below is reads only: no Set VCP was sent to it. The probes come from the debug build in `.build-ddc`, with the app quit.

**Before the changes**, `Glow --probe-displays` (AOC part; the built-in display read 68 %, native):

```
Discovery took 12280 ms and found 2 display(s).

== 32G2WG3 (display 3)
   identity: vendor 0x5E3, product 0x3202, serial present
   transport: External connection
   framebuffer: IOService:/AppleARMPE/arm-io@10F00000/AppleH16GFamilyIO/dispext0@84000000/IOMobileFramebufferShim
   matched: registry ID 0x105502F64, score 18, by framebuffer location, EDID vendor, EDID product, EDID manufacture date, EDID image size, vendor, product, serial number, product name
   service: 32G2WG3, link unnamed
   note: DDC/CI: Standard DDC/CI (source 0x51, one send, checksums checked)
   note: No capability report: The display took too long to answer.
   note: Safe mode: reading only, until Glow is reopened
   capability string: none (The display took too long to answer.)
   reads: none (Glow reads only codes the report lists)
   settings:
   - Brightness: 100%; route Software dimming; evidence Inferred from connection; access readWrite; editable
     The display didn’t answer DDC over this connection. Glow dims the picture instead; the backlight doesn’t change
   - Resolution: 1920 × 1080; route Native control; evidence Tested successfully; access readOnly
   - Refresh rate: 144 Hz; route Native control; evidence Tested successfully; access readOnly
```

**Why it's silent.** A throwaway diagnostic, kept out of the repo, sent single requests straight over IOAVService to the AOC's matched service, `0x105502F64`, at chip `0x37`. Each sent request was written in 1–2 ms; every read then failed the same way.

| Try | Bytes sent | Read result |
| --- | --- | --- |
| Get VCP 0x10, source 0x51, read waits 50 / 100 / 200 / 400 ms | `82 01 10 AC` | `0xE0114103` after 6052–6078 ms, each |
| Two write cycles, as MonitorControl does, checksum seeded with `0x6E` alone, waits 40 / 50 ms | `82 01 10 FD` | `0xE0114103` after about 6040 ms |
| Alternate source `0x50`, waits 50 / 200 ms | `82 01 10 AD` | `0xE0114103` after about 6035 ms |
| Chip `0xB7` instead of `0x37` | `82 01 10 AC` | `0xE0114103` after about 6036 ms |
| Capability request, offset 0, waits 50 / 200 ms | `83 F3 00 00 4F` | `0xE0114103` after about 6036 ms |
| A bare read, no request | none | `0xE0114103` after 6038 ms |
| Eight more Get VCPs, 1 s apart | `82 01 10 AC` | `0xE0114103` after 6030–6035 ms, all eight |
| Reply read at data address `0x51` | `82 01 10 AC` | `0xE0114103` after 6038 ms |
| **EDID** over I2C, chip `0x50`, 8 bytes | none | **OK in 1.5 ms**: `00 FF FF FF FF FF FF 00` |

So the I2C path through the hub works (EDID answers at once), but nothing at the DDC/CI address ever replies, on any timing or address. The likeliest cause is DDC/CI switched off in the AOC's own menu. The other plausible cause is the hub not passing DDC/CI through. Neither was confirmed: checking needs someone at the monitor's menu, or a direct cable.

**After the changes**, `Glow --probe-displays` (AOC part; built-in unchanged at 68 %):

```
Discovery took 24677 ms and found 2 display(s).

== 32G2WG3 (display 3)
   identity: vendor 0x5E3, product 0x3202, serial present
   transport: External connection
   framebuffer: IOService:/AppleARMPE/arm-io@10F00000/AppleH16GFamilyIO/dispext0@84000000/IOMobileFramebufferShim
   matched: registry ID 0x105502F64, score 18, by framebuffer location, EDID vendor, EDID product, EDID manufacture date, EDID image size, vendor, product, serial number, product name
   service: 32G2WG3, link unnamed
   note: DDC/CI: no reply on any profile tried (Standard, Slower timing, Alternate address)
   note: No capability report: The display didn't reply; the connection gave up waiting (IOReturn 0xe0114103).
   note: Safe mode: reading only, until Glow is reopened
   DDC/CI tries:
   - Standard, capability report: no reply after 6106 ms · The display didn't reply; the connection gave up waiting (IOReturn 0xe0114103).
   - Standard, Get VCP 0x10 (brightness): no reply after 6124 ms · The display didn't reply; the connection gave up waiting (IOReturn 0xe0114103).
   - Slower timing, Get VCP 0x10 (brightness): no reply after 6305 ms · The display didn't reply; the connection gave up waiting (IOReturn 0xe0114103).
   - Alternate address, Get VCP 0x10 (brightness): no reply after 6105 ms · The display didn't reply; the connection gave up waiting (IOReturn 0xe0114103).
   Working profile: None answered
   Capability string: None (The display didn't reply; the connection gave up waiting (IOReturn 0xe0114103))
   Reads: none
   settings:
   - Brightness: 100%; route Software dimming; evidence Inferred from connection; access readWrite; editable
     The display didn’t answer DDC over this connection. Glow dims the picture instead; the backlight doesn’t change
   - Resolution: 1920 × 1080; route Native control; evidence Tested successfully; access readOnly
   - Refresh rate: 144 Hz; route Native control; evidence Tested successfully; access readOnly
```

What changed:
- Every profile is tried, with each try's time and the real IOReturn, instead of a bare "took too long".
- Each dead exchange costs one wait of about 6 s, not one per retry: the retry window stops retries on a bus that blocks.
- The OSD still shows only what's true: software dimming for brightness, and no DDC setting.
- Discovery costs about 25 s on this connection at launch and on Refresh Displays. Wake and reconfiguration after that send one quick standard Get VCP, about 6 s.

**AOC brightness write → read-back → restore: not done.** The AOC never answered a read, so there was no value to read first and nothing to confirm a write against. My rule for real monitors is to write only after a successful read, so none was sent.

### AOC 32G2WG3, brightness sent without a reply, 2026-11-09

The AOC was still behind the Anker hub, on HDMI through the adaptor, and I had checked its menu. A read-only `--probe-displays` first: matched (now service `0x100004AE8`), and still no reply on any profile. Then, with me reading brightness 50 from the AOC's own menu and watching the screen, `Glow --brightness-pulse 50` sent Set VCP `0x10` only: 40, 50, 40, 50, then 50 again, 3 s apart. Nothing else was sent. It ran once on each profile:

| Profile | Each send accepted by the connection in | What I saw |
|---|---|---|
| Standard | 66–69 ms | No change |
| Slower timing | 100–106 ms | No change |
| Alternate address | 66–69 ms | No change |

Every send left the Mac without an error, and none reached the monitor. Taken with the silent reads, and with DDC/CI not switched off in the menu, the hub (or the HDMI adaptor) doesn't pass DDC/CI, in either direction. Glow keeps software dimming for this monitor, and a mode for monitors that take commands but don't reply isn't needed.


### Displays already connected at launch, 2026-11-09

With the AOC already plugged in through the hub, Glow showed no displays at all for about 25 s after it opened. Two things caused it:

- Discovery returned every display at once, so the built-in display waited for the AOC's probe.
- The AOC's probe climbed the whole ladder: four requests, each blocked for about 6 s and then refused.

After the fix (ADR 0001, decisions 16 and 17), with the app quit, `Glow --probe-readings` (read only) printed:

```
21 ms: MacBook Air shows
21 ms: MacBook Air is ready: Native control
21 ms: 32G2WG3 shows, being checked
6143 ms: 32G2WG3 is ready: Software dimming
Discovery took 6143 ms and found 2 display(s).

== 32G2WG3: Software dimming
   tried: Standard, capability report: no reply after 6124 ms · The display didn't reply; the connection gave up waiting (IOReturn 0xe0114103).
   note: Glow stopped there: the connection waited 6.1 s, then refused the request, which no other profile changes. Some hubs and adapters don’t pass DDC/CI.
```

- The built-in display is usable at 21 ms, not 25 s, and the AOC is ready at 6.1 s, not 25 s.
- On the test Mac, a debug bundle with `-GlowSimulatedMonitors all` showed the Dell and both LGs on hardware control while the AOC C24G2, the slow one, said "Checking connection…". It then switched to hardware control. After Refresh Displays, every row stayed filled the whole time.
- Tests: `DiscoveryProgressTests.swift` (3), three stall tests in `DDCDiscoveryTests.swift`, and one in `SimulatedMonitorTests.swift`.
- The same Mac at a real login, where the hub's service can appear late, wasn't tried.

### Not verified

- DDC/CI on a real monitor that answers: the capability string, Get VCP, the brightness and contrast write → read-back → restore, and how long each takes. The AOC was connected later but never answered a DDC/CI read (above). Brightness sent without a reply didn't reach it either, on any profile (above), so the hub is the block. Next step: connect it with a USB-C to HDMI or DisplayPort cable that carries DDC/CI, without the hub, then run `--probe-displays` again. If it answers, run the same checks under the same rules: read first, change by 10 or less, brightness `0x10` and contrast `0x12` only, restore at once and read the restore back.
- A profile ladder that ends in success on real hardware: slower timing or the alternate address getting the first reply. The AOC was silent on all three, so the success paths are unit-tested only (`DDCDiscoveryTests.swift`).
- The no-report fallback ("Answered, not listed by the display") on a real monitor. It's covered by unit tests and the demo display in the `pane-connection-unlisted` snapshot only.
- Refresh Displays in the running app re-running every profile, and the OSD updating without a relaunch. The store hook (`GlowStore.refresh()` → `retestSilentConnections()`) is in place, but the GUI wasn't launched. Refresh is in Settings › General and on a right-click of the menu-bar mark.
- Matching a display to its `DCPAVServiceProxy` on real hardware, and two identical monitors getting different identities.
- Software dimming on an external display whose DDC doesn't answer. It's tested only on the built-in display, through the self-test.
- The brightness-key event tap, the Accessibility grant flow and Settings › Controls' **Allow…** button. They need the GUI app, which this pass didn't launch.
- Open at login from `build/Glow.app`, for the same reason.
- Pausing and resuming writes around sleep, wake and plugging a display in or out, with real hardware. Covered by unit tests on the pipeline only.
- Safe mode (Shift at launch) in the app. `--probe-displays` uses the same safe-mode adapter, but the Shift check at launch wasn't exercised.
- Intel Macs. The bundle has an x86_64 slice that wasn't run.
- The alternate DDC address (ADR 0001, decisions 8 and 13). It's now tried per connection during discovery, and live on the AOC it got no reply. Retrying one silent setting on the other address isn't built.

## Brightness Match: not verified

- The full-screen grey patches on real displays: that each covers its screen, sits above other windows and below the calibration window, and is dimmed by software dimming on the AOC as the code expects (gamma dims everything on that screen).
- The calibration window live: the ←/→ and ↑/↓ key monitor, Esc and the close button cancelling, and coming to the front over a full-screen app.
- A real match end to end on the built-in display and the AOC, including the restore after Cancel and after Save, checked by reading back.
- The AOC over DDC/CI. It didn't answer in this pass, so it would be matched over software dimming. A later DDC answer would make that match "out of date", as the tests expect.
- Auto-brightness or True Tone moving the built-in display during a match. The intro warns that it may drift and says where to turn automatic brightness off, but nothing detects it.
- Real sleep, wake or a display being plugged in during a match. The session waits out a pause and a stale layout in tests only.
- The Forget Match confirmation dialog. It isn't in the snapshots.
- That the brightness keys follow curves on real hardware. Key routing through curves is unit-tested; the event tap needs the GUI app.

## Scenes and the control audit, 2026-11-08

Scenes, Restore Starting Values and Reapply settings after wake are built (see Scenes in [docs/development.md](docs/development.md#how-it-works)). Every scene-shaped write goes through `GlowStore.confirmWrite`, the same path as a slider, so each value is validated, written, read back and paused around sleep.

### Scenes on this Mac's displays

`--scene-selftest` runs on the real displays through the real store, with a throwaway defaults suite. It uses only brightness and contrast on a hardware or native route, moves each by 5 and reads every value back. Here only the built-in display qualified; the AOC is on software dimming and didn't answer DDC/CI.

```
Displays: Built-in Retina Display (Native control)
  Built-in Retina Display: Brightness 69%
PASS  scene applied: Applied to 1 setting
PASS  every shifted value reads back from the display
PASS  the shifted scene is active
PASS  original scene applied: Applied to 1 setting
PASS  every original value reads back
PASS  the forgotten values read as the originals
PASS  nothing is reapplied while the option is off
PASS  after wake, Glow put back what it set
PASS  every reapplied value reads back
PASS  Built-in Retina Display restored to its starting values
PASS  every value is back to where Glow found it
PASS  a disconnected scene says so: None of this scene’s displays are connected
PASS  native level 0.6856319 restored exactly (reads 0.6856319)
PASS  final read: everything as found
All scene checks passed.
```

"After wake" here calls the reapply step directly once the value has been changed behind Glow's back. The Mac didn't sleep.

### Bugs found and fixed

- **Scene editor layout.** In a grouped form, a section with a footer inside a `ForEach` drew its rows and its footer side by side as one unboxed row, with the header repeated. Each display section now ends with a caption row instead of a footer. Seen in `scene-editor`, `scene-editor-saved` and `scene-editor-away`.
- **Restore Starting Values said "Nothing to change" after a scene had changed the display.** It compared the starting values with the display as it was when the button was drawn. It now compares with the display as it is now (`restoreComparesWithTheDisplayAsItIsNow`). Seen in `settings-displays-restored`: "Restored 3 settings", and the values are back to 68 %, 35 % and sRGB.
- **The Scenes pane's empty state sat off-centre.** Seen in `pane-scenes-empty`.
- **An OSD picker or switch without a reading showed a guessed value** (the first option, or Off), against ADR 0001. A picker now shows "No reading yet", and a switch shows its value text in place of the switch. The demo displays always have readings, so this state isn't in a snapshot.

### Every control, with its verdict

Nothing was clicked in a live window; this pass didn't launch the GUI. Each verdict comes from reading the code, the unit tests, the snapshots and, where it says so, the hardware self-test.

| Where | Control | Verdict |
| --- | --- | --- |
| Glow Desk | Refresh Displays (right-click menu) | **Works; the right-click itself not verified.** Calls `store.refresh()`; disabled while Glow is looking for displays (`StatusMenuTests`). It's on a right-click or Control-click of the menu-bar mark, since the popover lost its gear menu. |
| Glow Desk | Display rows | **Honest.** Name and how Glow controls it, as quiet text. Software dimming is orange and says "Dims the picture, not the backlight". A connection with nothing everyday says "No everyday controls on this connection". The row's context menu, Display Settings…, opens Displays on that display. |
| Glow Desk | Row sliders (brightness, volume) | **Works.** Through `store.update` and the write pipeline, read back. A native write through the same pipeline is confirmed by the self-test; dragging wasn't tried live. Volume only appears when the display can change it. |
| Glow Desk | Scenes line (under the header) | **New.** One icon button per scene, its symbol, chosen while the displays match it; the name is the help and the VoiceOver label, with "Active". **+** starts a new scene in Settings › Scenes. When they don't all fit, **…** opens Settings › Scenes; it never wraps (`popover-many-scenes`). With none, just **+**. An input change asks first. Scene buttons are disabled while paused, in safe mode, or while one is applying; the whole line while paused or with no displays. A scene that didn't fully apply says so underneath, with its detail as help. |
| Glow Desk | Match line | **Honest**, read only. A green dot and "Displays are appearance matched", or "Not matched yet" with **Match displays…** (a Glow button), which opens Brightness Match. Hidden with one display. |
| Glow Desk | Brightness keys | **Changed.** Four Glow buttons in one row, a symbol over a short name (All, Cursor, Focused, Mac), the chosen one lit; the full name is the help and the VoiceOver label, with the selected trait. A caption says when the keys go to macOS (demo displays, safe mode, no Accessibility, run from a terminal) and which display Focused means now. **Allow…**, a Glow button, opens Settings › Controls, and only appears in the app bundle (`popover-keys-allow`). |
| Glow Desk | More controls… | **Works.** A Glow button at the footer's trailing edge, alone there. Opens Settings › Displays. |
| Glow Desk | Settings… (right-click menu, ⌘,) | **Works; the right-click itself not verified.** Opens Settings. ⌘, is also the app menu's Settings…. |
| Glow Desk | Quit Glow (right-click menu, ⌘Q) | **Works; the right-click itself not verified.** Quits; software dimming hands the table back to ColorSync on the way out. |
| General | Open at login | **Honest; not verified from the bundle.** `SMAppService.mainApp`. Under `swift run` it's disabled and says why. When approval is pending it says where, with **Open Login Items…**. A failure shows macOS's reason. |
| General | Show overlay on change | **Works.** Saved; in the snapshots. |
| General | Use demo displays | **Works.** Switches adapters, hands software dimming back, and keeps the person's scenes apart (tested). |
| General | Refresh Displays | **Works.** "Refreshing…" while discovering; the DDC tests cover re-testing silent connections. |
| General | Reapply settings after wake | **New**, off by default. It runs after a wake, once discovery has run again and writes have resumed. It never changes input or power. The step itself is confirmed on the built-in display; a real sleep wasn't tried. |
| General | Open Tutorial… | **Works.** Opens setup as a tutorial (the setup tests). |
| Displays | Display tiles | **Works.** Choose which display's OSD shows; each says its route. One snapshot per display. |
| Displays | Slider rows | **Honest.** Through the pipeline. With no reading, the value beside it says "No reading yet", and the thumb sits at the minimum. |
| Displays | Picker rows (colour preset, picture mode) | **Fixed.** See above. |
| Displays | Switch rows (mute) | **Fixed.** See above. |
| Displays | Action rows | **Not on the OSD.** The catalog's only actions are the three resets, which are destructive and appear only in Settings › Connection, never as buttons. |
| Displays | Read-only rows (resolution, refresh rate, HDR, gamma, hours used) | **Honest.** Shown, never written. |
| Displays | Unavailable rows | **Honest.** "Not available on this connection". |
| Displays | Input | **Asks first.** "Switch your Dell U2723QE to HDMI 1?". Demo only: I never write input to a real monitor in testing. |
| Displays | Display power | **Read only.** Never written; in the demo, "Reported, but test failed". |
| Displays | Open Brightness Match, Open Connection | **Work.** They open those panes, which have their own sections. |
| Displays | Control mode | **Works.** The same setting as Settings › Controls, now a row of four Glow choice buttons under the label instead of a pop-up. |
| Displays | Scenes row and Open Scenes | **New.** Names the scenes this display is in ("Part of Work, Night, and Presentation"). |
| Displays | Restore Starting Values | **New.** Writes back what was read at launch through the pipeline, and skips anything that wasn't read. Disabled, with "Everything Glow read at launch is as it was.", when nothing differs. An input change asks first. Confirmed on the built-in display by the self-test. |
| Controls | Brightness keys: Allowed / Allow… | **Honest; not verified.** **Allow…** calls `KeyAccess.request()`. It's disabled under `swift run`, which says the grant would go to the terminal. The grant itself needs the bundle. |
| Controls | Brightness keys change (tiles) | **Works.** Saved. Key routing is in `BrightnessKeyTests`. |
| Controls | Focused display | **Works.** A Glow menu trigger (the name and a small chevron). Lists the displays connected now, or "No displays". The choice is saved, except a demo display's. |
| Controls | Fine adjustment | **Works.** Saved; 1/64 steps are in `BrightnessKeyTests`. |
| Controls | Preview Overlay | **Honest.** Disabled, with "No display has a brightness reading to show yet.", when nothing has a reading. |
| Scenes | New Scene from Current Settings | **New.** Disabled, with "Connect a display Glow can read first.", when nothing can be captured. |
| Scenes | Apply *scene* | **New.** "Applying…" while it runs; an input change asks first (`confirm-scene`); the result shows under the scene. Disabled while paused and in safe mode. |
| Scenes | Edit…, Move Up, Move Down, Delete… | **New.** Move and Delete sit behind a ⋯ Glow menu trigger in the scene's header. Move is disabled at the ends; Delete asks first. |
| Scene editor | Name, Symbol | **New.** Save is disabled, with "Name the scene" or "Include at least one setting", until both are there. Until a name is typed, the name follows the symbol: the moon makes it "Night", and Other goes back to the name Glow gave it. A saved scene follows only while its name is its symbol's. |
| Scene editor | Include check button, value control, Use Current Values | **New.** A setting can join only with a value Glow has read. Input is marked "Asks first". Power is listed but can't be ticked ("Never part of a scene: it can turn the display off."). Read-only settings and actions are left out, with a count. |
| Scene editor | A display that's away | **New.** Its saved values stay and can only be removed (`scene-editor-away`). |
| Scene editor | Delete Scene…, Cancel, Save | **New.** Glow buttons; only Save has a symbol, an accent checkmark, so it reads as the main action. Return saves and Esc cancels (keyboard shortcuts, not tried live); Save stays disabled until the scene has a name and a setting. Delete asks first; Cancel discards the copy. |
| Glow | Quit Glow | **New.** Settings › Glow shows the mark, the version ("Development build" under `swift run`) and **Quit Glow**, which calls `NSApp.terminate`, so software dimming hands the table back the same way. Not clicked live. |
| Brightness Match, Connection | All | **Not audited here.** See their own sections. |

### Not verified (scenes)

- Reapply after a real sleep and wake. The wake handler calls it once writes resume, and the self-test runs the step itself, but the Mac wasn't put to sleep.
- Clicking any control in a live window, and VoiceOver on the scenes row, the Scenes pane and the editor.
- Scenes over DDC/CI on a monitor that answers. The AOC didn't, so only native brightness was written.
- Scenes on a software-dimmed display. The self-test leaves software dimming alone; it's covered by the demo and unit tests only.
- The input confirmation on real hardware. I never write input to a real monitor in testing.
- The picker and switch with no reading, on screen. The demo always has readings.
- Open at login and the Accessibility **Allow…** flow from `build/Glow.app` (already listed above).

## Glow Desk redesign, 2026-11-08

- **Narrower.** 360 → 308 pt, as narrow as the four brightness-key buttons allow with "Focused" unclipped. "Mac only" would need about 314 pt, so the buttons say "Mac" and "Cursor", and the full names go to the help and VoiceOver.
- **No native-looking controls** but the sliders: no pop-ups, gear menu, link buttons or checkmark menus. Every button is `ActionButtonStyle`.
- **Right-click on the mark.** `MenuBarExtra` stays. A local event monitor (`StatusItemMenu.swift`) takes a right-click or Control-click on Glow's status-bar window, found by its `NSStatusBarButton`, before `MenuBarExtra` sees it, and pops the menu up under the mark. A plain click still opens the popover.
- **Opening.** The content is fully shown from the first frame. It only settles from 98.5 % to full size over 90 ms, anchored at the top, and under Reduce Motion it doesn't move.

### Not verified (Glow Desk)

- The real right-click and Control-click on the menu-bar mark: that `event.window` is the status-bar window, that the menu sits under the mark, the mark's highlight while it's open, and that `MenuBarExtra` doesn't also open or close the popover. This pass didn't launch the GUI.
- The real opening: how fast it feels, and whether the settle plays on every opening (it runs from `onAppear`).
- VoiceOver on the brightness-key buttons (name and selected) and the scene buttons (name and "Active").
- ⌘, while the popover is open, now that it relies on the app menu's Settings….
- More than one screen, larger text and Increase Contrast.
- The sliders' accent colour on screen. Off screen, inactive windows draw it grey.

## Settings: Glow pane and Glow controls, 2026-11-08

- **Glow pane.** Settings › Glow, last in the sidebar under Support, as About is in Tuck and Hum. Its tile is the app icon, the mark in white on the brand colour. **Quit Glow** inside Settings is at the end of General (moved 2026-11-09). The sidebar's section that held Controls and General is now "App", so no section shares the pane's name.
- **No native pop-ups or checkboxes in Settings.** Control mode is a row of choice buttons. The OSD pickers, Controls › Focused display, the Match reference and each scene's ⋯ menu are Glow menu triggers: the current value and a small chevron, opening the system menu. The scene editor's Include boxes and Setup's "Open Glow at login" are check buttons that VoiceOver reads as checkboxes, with their state. Use Current Values and the away display's Remove are Glow buttons. Sliders, switches, text fields and the choice tiles stay as they were. Input still asks first, through the same confirmation.
- **Connection.** "Connection details" is now "Connection" everywhere it's shown. The saved pane value is unchanged, so Settings still reopens on it.
- The scene editor's Delete Scene…, Cancel and Save are Glow buttons too, with Return and Esc kept. Left native: setup's Back and Start Using Glow, the window's own push buttons.
- Setup's Done step now says where things are since the popover changed: click Glow's mark for the displays and scenes, right-click or Control-click it to refresh or quit, and Settings… is in that menu or behind More controls….

### Not verified (Settings)

- Clicking anything in a live window: the choice buttons, check buttons, every menu trigger opening its menu and choosing an item, and **Quit Glow** quitting. This pass didn't launch the GUI.
- VoiceOver on the check buttons (meant to read as checkboxes with their state), the choice buttons (selected state) and the menu triggers (label and value).
- "Open Glow at login" switched on, on screen: under `swift run` it's disabled, so the snapshots show only that state.
- Return and Esc in the scene editor now that its footer uses Glow buttons, and Save disabled on screen. No snapshot has a scene that can't be saved.
- The version line from `build/Glow.app` ("Version 0.1.0 (1)" from its Info.plist). It's unit tested; the snapshots run unbundled and show "Development build".

## Keys, popover, setup and reading, 2026-11-09

Four areas of work, integrated on 2026-11-09. Each item says how it was checked.

### Brightness keys, step size and the overlay

- **Why holding lagged.** Each press wrote, read back and retried before the next could start. On DDC/CI that's about 240 ms a press, while a keyboard repeats every 33–83 ms, so presses queued up and kept landing long after the key came up.
- **The write path** is now latest value wins, one write in flight per display and setting (`WriteCoalescer`). Values a newer one overtakes are never sent, intermediate writes skip the read-back, and the last value of each run is read back and confirmed. `confirmWrite` (scenes, Restore Starting Values, Brightness Match) drops anything queued and confirms as before. ADR 0001, decision 4, is amended. Checked by `KeyWriteTests` and `--hold-selftest`.
- **A held key** ramps 1 % every 20 ms on Glow's own timer after the keyboard's repeat delay (clamped to 0.25–0.5 s). It stops on key-up, the other key, the tap being disabled, the range end, a pause, the keys going to macOS, or 233 ms of silence. Repeats are swallowed and never add a step. Checked by `KeyHoldTests` with an injected clock. A keyboard that sends no repeats gets its step and about 0.23 s of ramp.
- **Brightness step:** Like macOS (1/16), 1, 2, 5 or 10 %, on the step's grid; the fine step is a quarter, at least 1 %. Settings › Controls › Adjustment, with the keys footer following the choice.
- **Look:** Slider or Boxes, a `VisualChoice` in Settings › Controls.
- **The overlay** shows on each proposed change, updates one panel in place, and fades 1.5 s after the last change (none under Reduce Motion). Boxes is Apple's square HUD; Slider gains a level bar. `keys/hud-*`, light and dark.

### Glow Desk: boxes, rounder buttons, Quit

- **Boxes** (`LevelBoxes.swift`): 16 rounded boxes with continuous corners when the look is Boxes. Click a box to light it and those before it; click the top lit box to step down one (so the lowest level is reachable); drag for any level. One adjustable accessibility element, arrow keys move one box. `LevelBoxTests` covers the fill, click, step and hit-testing maths; `popover/boxes-*` the states. The overlay's boxes use the same `LevelBoxScale` fill (unified at integration).
- **Rounder buttons** on Glow Desk only (`ActionButtonStyle(rounded:)`): text buttons are capsules; the square symbol buttons use 8.8 pt corners, because above 0.4 × height the stroke showed ticks at the corners. Settings' buttons are unchanged.
- **Quit Glow** moved from Settings › Glow to the last section of Settings › General ("Leave the menu bar"). The right-click menu keeps it.

### Setup

**Superseded in part, 2026-11-19:** see "Setup cut to what teaches, 2026-11-19" below. The welcome, Set your brightness and You're set are gone; matching is unchanged apart from its copy, and setup no longer shows the move-together check button.

- **Four steps, all real:** Welcome (no animation, so Get Started works at once) → Your displays (a live slider per display and a plain line on how Glow sets it; reading, none, one, demo and paused states) → Match their brightness → You're set (where Glow lives, **Allow…**, **Open Glow at login**). The tutorial runs the middle two and ends with Done. Deleted: the pretend desk, tour, key sandbox and brand intro, with their tests and snapshots.
- **Matching** is a real Quick Match `MatchSession` inside setup, with the same patches and the same `MatchCompare` form, saved as Settings › Brightness Match saves. Cancel, Esc, Back, closing and finishing all put back every display it changed. With one display the step is "Set your brightness". **Not Now** skips it.
- **Two choices to review:** saving a match in setup turns on **Move matched displays together** (shown as a check button that can be turned off), so the popover slider visibly moves both. And as before, a save records Quick as the method, so Settings › Brightness Match opens on Quick afterwards.
- Checked by `SetupTests` (mock adapter and fake patches) and every step in `setup/`, light and dark. `BrightnessMatchTests` is unchanged and passes; the calibration window's snapshots are byte-identical.

### Reading displays (ADR 0002)

- **Rereads** in two tiers, only reads, through `GlowStore.reviseSetting`, which merges one setting at a time and leaves alone any setting with a change on its way. Pause, pending and write-quiet skips, back-off, the 60 s mark and "reads never write" (`totalWrites == 0`) are covered by `ReadingTests` with an injected clock. The coalescer keeps `pendingValue` set for a whole run, so a held key or a drag is never pulled back by a reread.
- **Settings › Reading:** Keep readings fresh, Read All, At launch, Wake (moved from General) and Patience. `reading/pane-reading*`.
- **Read Again** with the read age and what it found; **Hide on This Display** and the Hidden by you list; codes outside the catalog read once and listed in Connection, never writable. `reading/pane-displays-*`, `reading/pane-connection-reported`.
- **The change mark** shows in Settings › Displays and, added at integration, in Glow Desk's row header in place of the route label for a minute (`popover/boxes-changed`). A failure still takes the header.

### Built-in brightness reading

macOS's `DisplayServicesGetBrightness` answered 0 % on one read-only run and 100 % on the next, with success codes, while the IORegistry showed `BrightnessMilliNits` 168668 (about 169 nits). A third run, at integration, read 100 % again. Which is true isn't settled. Rereads drop a native 0 and keep the last value. Discovery's own first reading isn't guarded: if it reads 0, the first brightness key press starts from 0. To check: open Glow Desk and compare the MacBook row with the real brightness.

### Not verified (2026-11-09)

- **Real keys:** holding a brightness key on the MacBook and an external keyboard, and whether repeats arrive at `NSEvent.keyRepeatDelay` / `keyRepeatInterval`. The hold on real DDC/CI hardware (none answers here) and on the built-in display.
- **The overlay on screen:** position, HUD vibrancy (flat grey off screen), the linger and fade, Reduce Motion, VoiceOver.
- **Boxes with a real pointer:** hover, click, drag feel and latency in the live popover; Tab focus and the arrow keys; VoiceOver adjust.
- **Setup:** a real match on two displays (patches on each screen, setup above them, restore on Cancel/Esc/Back/close), Allow… and the grant being noticed, Open at login applied.
- **Reading on real hardware:** DDC/CI rereads, back-off, Patience's relinking, Hide, and At launch › Put back what Glow last set (never turned on against real hardware). While Glow is open stopping when Glow Desk and Settings close. How often "Changed outside Glow" fires on a built-in display with automatic brightness on.
- **Quit Glow** in General actually quitting (same call as before; not clicked).
- Setup's Your displays step draws sliders even when the look is Boxes. *(Settled 2026-11-19: the step uses Glow Desk's own rows, which follow the Look.)*

## In the app, on the test Mac, 2026-11-09

The in-app checks ran on a test Mac: the arm64 bundle in a macOS 15.6.1 virtual machine (1280 × 800). Its one display, "Apple Virtual", can't be set by macOS, so Glow dims it in software. Demo displays and simulated monitors stood in where a check needed more.

- **Verified:**
  - Setup finds Apple Virtual on software dimming.
  - Glow Desk opens and closes from the mark. Its More controls… and Match displays… open Settings in front, active, with Glow Desk closed.
  - The right-click menu: Settings… opens Settings in front and active, and Quit Glow quits.
  - Settings › Displays: the slider, with its value read back.
  - Brightness Match with one display.
  - Scenes: a new scene from current settings, applied, then tagged Active.
  - Controls: **Allow…** brings up macOS's Accessibility prompt. **Preview Overlay** shows 5 of 16 boxes at 33 %.
  - Reading › Read All. General › Use demo displays, on and off. Open at login: macOS shows "Login Item Added".
  - Connection › Copy Report: 76 lines, with serial numbers `[redacted]`.
  - The Glow pane.
- **Bug found and fixed:**
  - **Glow Desk stayed open over Settings.** More controls… turned Settings to Displays behind Glow Desk, which stayed on top. Three fixes didn't hold:
    - closing Glow Desk's window directly left the mark thinking it was open, so the next click on it did nothing;
    - closing it first, by clicking the mark, then opening Settings, and doing the same with Settings opened a moment later, both left Settings in front but not in use.
    With no other Glow window open, closing Glow Desk hands the Mac back to the app in use before it opened. Now Settings opens first and the mark is clicked after (`SettingsWindowPresenter.show`). On the test Mac, Glow Desk closes, Settings is active, and one click on the mark opens Glow Desk again.
- **Polish, not changed:**
  - The overlay card can cover part of setup or Settings.
  - With one display, setup's second and third steps show the same slider. *(Settled 2026-11-19: with one display there's no match step.)*
  - **Allow…** shows macOS's prompt and opens System Settings at the same time.
  - **Move matched displays together** stays enabled when there's nothing to match.
  - Connection shows "Write reliability: Not yet tested" next to "Tested successfully". One is about writes and the other about reads, but side by side they look like a contradiction.

### Not verified on the test Mac

- The brightness keys and the event tap. Accessibility wasn't granted on the test Mac.
- Hardware and native control. The test Mac's display has neither.
- How software dimming looks: the test Mac's screenshots don't show gamma changes.
- VoiceOver, keyboard focus and ⌘W.

## Simulated DDC/CI monitors, 2026-11-09

No monitor here answers DDC/CI (see "AOC 32G2WG3 over DDC/CI"), so debug builds can put four simulated monitors in place of real ones. Each is monitor firmware written in Swift that speaks DDC/CI bytes. It checks every checksum, answers Get VCP and capability requests with real framing, keeps its own values, and logs each request. Each has a real monitor's capability report, from ddcutil's reports, and quirks chosen to send Glow down one path:

| Model | Quirks | What Glow has to do |
| --- | --- | --- |
| `dell-u3011` | A change shows in reads 90 ms after it's set. | Stay on the standard profile, and catch the late value on the second read-back. |
| `aoc-c24g2` | Answers 120 ms after a request, and is busy for 100 ms after a change. | Climb to Slower timing; its double send covers requests dropped while busy. |
| `lg-27md5kl` | Answers only the alternate address (source 0x50), and pads the report's last fragment with NULs. | Climb to Alternate address, and read the padded report correctly. |
| `lg-29um69g` | Sends no capability report, and every fifth reply is garbled. | Read each setting it knows (11 answer; 7 are editable), and ask again after a garbled reply. |

- **`--simulated-selftest`:** **Pass.** It found all four in 8.4 s, each on the profile above. On each it raised brightness by 5, read it back, confirmed it and restored it, and each monitor ended at its starting value. 0 requests were rejected. The AOC dropped 2 requests while busy on each change, and the double send covered them.
- **In the app**, on the test Mac, run with `-GlowSimulatedMonitors all`:
  - Glow Desk and Settings › Displays show all four on hardware control.
  - A box click on the AOC set 69 %, the overlay showed it, and Connection says "1 of 1 writes confirmed".
  - Connection shows the AOC's tries: Standard got no reply, and Slower timing answered.
  - The LG 29UM69G's settings say "Answered, not listed by the display". Its input and color preset are shown but can't be changed, since nothing lists their values.
- **`SimulatedMonitorTests.swift`** (21 tests): the firmware's framing and checksums; discovery, the profile and the editable settings on each model; confirmed writes, read-back and restore; a held key's ramp; a scene; and safe mode. On every model, discovery writes nothing, every request is one the firmware accepts, and only the setting asked for is written.
- **What this proves:** Glow's DDC/CI path works end to end against firmware that speaks real bytes, with real capability reports. That covers discovery and the profile ladder, reading the capability report, confirmed writes with read-back and retry, the held-key ramp, scenes and safe mode.
- **What it doesn't prove:** how a real panel responds, a real hub's, dock's or adaptor's timing, IOAVService's own timing and errors, or anything about the built-in display, gamma or DisplayServices. The quirks were chosen to exercise each path, not measured on hardware.
- **Only in debug builds:** the release binary has none of the flags or names (see Results). A simulated run uses the real preferences.

## Trial and license keys, 2026-11-09 to 2026-11-16

A 7-day trial and license keys were built and tested on 2026-11-09, and removed on 2026-11-16. Glow is free. Every feature works for everyone, with no trial, license key or Buy Glow.

- **Built, 2026-11-09:** 31 new tests, 20 snapshots, and a run on the test Mac. That run found a key's issue day shown a day early west of UTC; it was fixed, with one more test. Settings › Glow's Links (website, support, privacy policy and license agreement) came in with this work and were kept.
- **Removed, 2026-11-16:** the License pane, the "Your trial has ended" notice, Enter License… and Buy Glow… in the right-click menu, and the trial's hold on writes, the brightness keys and scenes. So are `scripts/make-license.swift`, the embedded public key, and the purchase link in `Info.plist` and `release.env`. `release.sh` no longer checks for a development key.
- **Leftovers:** at each launch Glow quietly deletes `TrialRecord` and `LicenseKey` from its preferences, and the "Glow trial" login-Keychain item. The Keychain refuses, without a prompt, to let one build delete an item another build made, so an item from an earlier build can stay. It holds only the days the trial counted. Settings last left on the License pane open on Displays.
- **Tests:** 314, 0 failures (see Results). `LicenseTests.swift`, `TrialTests.swift` and `TrialGateTests.swift` are removed, and the right-click menu test now expects Refresh Displays, Settings… and Quit Glow. New: `theTrialsLeftoversGoAndGlowsSettingsStay` and `settingsLeftOnTheRemovedLicensePaneOpenOnDisplays`.
- **Legal drafts:** the EULA and privacy policy no longer mention a trial, keys, purchases or refunds. They still need legal review.

### Not verified (removal)

- That the Keychain delete works on every Mac. The tests check the preferences keys only. On this Mac, after the new build's first launch from `/Applications`, neither key nor the "Glow trial" item was left.
- The new build's windows weren't looked at on screen. The tests and snapshots cover the menu, Settings and Glow Desk.

## Setup cut to what teaches, 2026-11-19

ADR 0004 has the reasons. Setup is now at most four steps, each teaching one thing:

1. **Your displays:** Glow's mark at 32 pt and one line, then Glow Desk's own rows (`DeskDisplays`) at its 308 pt width. Beside them is "Click ✦ in the menu bar to open Glow Desk.", ticked when Glow Desk opens. A caption explains the route labels, and with demo displays a note says where to turn them off. States: demo, reading, none, one, own, opened and paused.
2. **Match their brightness**, only with two displays or more, and not in safe mode. Pick, compare, settling, matched, problem, and "Displays are asleep" while paused. **Not Now** skips it.
3. **The brightness keys:** **Allow…** with one line on why, the asked line, and the `swift run` note. Once access is on: "Access is on", then "Press a brightness key on your keyboard. The keys change every display.", ticked when a press changes a display. With demo displays, safe mode, Mac chosen for the keys or no displays, it says the keys work as they do without Glow.
4. **Open at login,** with the `swift run` note and the line on where the tutorial is.

The tutorial runs 1, 2 when it can, and 3 only once Glow can take the keys.

- **Removed:** the welcome page, setup's own sliders and their status lines, Set your brightness, the Try-it slider and move-together check button after a match, and You're set with its "In the menu bar" row. `SetupWelcome.swift` and the `title1` and `cardTitle` styles went with them.
- **Ticks:** `GlowStore.glowDeskOpens` (counted in `MenuBarView.onAppear`) and `GlowStore.keyPressesMoved` (counted in `handleBrightnessKey` when a press changes a display). Setup notes both when it opens. No timers.
- **Settings › General:** the Tutorial line now reads "Setup again, on your own displays."
- **Checked off screen:** every setup step and state in `setup/`, light and dark, all opened. `SetupTests` covers the step lists (two displays, one, none, safe mode, Mac only, a display leaving mid-step, tutorial), the ticks (Glow Desk opening, a key Glow takes, a key left to macOS), what a press changes for each key target, and the permission being watched only on the keys step.
- **Still demo-only:** `--snapshot-ui`'s setup desks use `MockDisplayAdapter`. The key-press shot calls `handleBrightnessKey` on a mock store, so no tap, overlay or hardware write is involved.

### Not verified (2026-11-19)

- Glow Desk's `onAppear` running on each real open from the menu bar, so the first step ticks.
- The grant being noticed on the keys step, then a real brightness key ticking it and changing the displays, with the overlay.
- VoiceOver reading each task and hearing "Done." when it ticks; Tab order through the steps; Increase Contrast; Reduce Motion.
- Open at login applied by Start Using Glow from the bundle.
- Glow Desk's rows in setup with the Look set to Boxes, in a real window.

## What the tests cover

| File | Tests | What they check |
| --- | --- | --- |
| `GlowAppTests.swift` | 18 | Capability rendering, value validation and snapping, write confirmation, retries and stale-layout rejection, calibration bounds, diagnostic redaction, identity. Pane titles (Connection, Glow, with the saved raw value kept) and the Glow pane's version line. |
| `CapabilityCatalogTests.swift` | 19 | The catalog covers every standard OSD setting, with no duplicate codes or IDs. Black levels are sliders once read. Gamma, menu language and hours used decode (2.2, English, 240 hours) and are never written. Capability-string parsing (well-formed, sloppy, missing, oversized). Evidence: reported settings aren't editable until a read succeeds; unknown and maintenance codes stay in Settings › Connection; refused or silent reads stay safe. Option names never expose raw codes. Encode/decode round trips. The demo OSD is generated from its report. Discovery only reads. Writes pause while suspended and on sleep. |
| `SceneTests.swift` | 26 | Capture: only confirmed readings (a stale or still-pending value is left out), no input, no power, no read-only settings, no display that's away. The plan: settings a display doesn't support on this connection, and power, are skipped with the reason; an out-of-range value is snapped and an unknown option skipped; a scene whose displays are all away sends nothing and says so, and one partly away names how many. Apply: "Applied 2; 1 couldn't be updated" from a refused write, and through the store the refused value is never shown as if it took. An input change asks first, goes last and can be left as it was while the rest applies; an input already set asks nothing. Active only while the displays show the scene's values. Settings: a blob without scenes, a damaged scene or setting costing only itself, an unreadable library leaving the other settings, a library from a newer Glow, a round trip. Demo examples never mix with the person's scenes and all apply on the demo displays. Reorder and delete. Restore Starting Values puts back what was read at launch (power is never a starting value) and compares with the display as it is now. Reapply after wake: off by default, puts back what a display forgot, only once, and never switches an input. Naming: a new scene's name follows the symbol and Other returns it to Glow's name; a typed name stays and a cleared one follows again; a saved scene follows only while its name is its symbol's. |
| `GlowSettingsTests.swift` | 16 | Partial, empty and unknown-enum settings blobs keep their defaults. The store round trip. The input confirmation names the display and the consequence. A scene asks first only for an input change. Slider snapping. Migration: an old saved `useDemoDisplays: true` that nobody chose becomes real displays; one someone chose stays. Settings left on the removed License pane open on Displays, and the trial's leftover keys are deleted while Glow's settings stay. |
| `DDCTransportTests.swift` | 32 | The profile ladder (Standard, Slower timing, Alternate address) and how each differs. A bus that refuses every read says why; a refused read then an answer still reads; a bus that blocks for seconds isn't retried; the slower profile waits longer and sends twice; the alternate profile uses source 0x50. Get VCP, Set VCP, capability and save packets byte for byte, checksums included, on both source addresses. Get VCP replies: good, bad checksum, unsupported, silent, malformed. Capability fragments and reassembly, including the end marker and the size limit. `DDCSession` on a scripted bus: retries, garbled vs silent vs unsupported, refused sends, never saving unless asked, and the capability read's retries and overall timeout. Discovery reads each listed setting once and never writes; a display that doesn't answer gets no settings and a reason. Service matching: every EDID field and the location count, identical monitors are told apart by location, no service serves two displays, and built-in or unrelated services never match. |
| `DDCDiscoveryTests.swift` | 13 | Discovery climbs the ladder until a profile answers, reuses the first answer, and never writes. A connection silent before gets one quick request and a note; one that answers then reads its report. A service that won't open sends nothing. Each route keeps its own working profile; Refresh forgets silence. With no report: one read of each catalogued setting, "Answered, not listed by the display", only low-risk sliders and switches editable, input, power and presets read-only, unnamed answers left out, and a report still decides when there is one. The demo logs, report lines, and Copy Report with discovery included and serials still redacted. |
| `BrightnessKeyTests.swift` | 24 | Telling repeats from fresh presses; a tap is one step of each size, on the step's grid; the fine step (a quarter, at least 1 %); 1 % steps on software dimming's range; the keys footer. Which displays each key target moves, and when the press goes to macOS (Mac only, demo, safe mode, no displays). 1/16 and 1/64 steps, stopping at the ends, and never stalling once rounded to whole percents. Decoding the system-defined key event. A demo store leaves the keys to macOS. Brightness Match: with every display as the target, matched displays follow their curves; without a match, or when a matched display is targeted alone, they don't; a follower never moves against the key; a missing reference or an out-of-date match isn't followed; followers stop at their ends. |
| `BrightnessMatchTests.swift` | 28 | Curves: Quick Match is a ratio through zero, including a display brighter than the reference, and needs a lit reference; Guided takes 3 to 5 points and passes through each; every curve is monotone and inside the display's range; the inverse; the ends; levels on each display's own range. Settings: an old blob without a match, an unreadable one, a round trip, one unreadable calibration among good ones, a saved curve that turns back is made monotone again, no chains of matches. Status: matched, out of date when a route changed, a reference alone. The store and a session on a fake adapter: discovery marks matched displays, Forget Match, keys through curves, the slider following only with **Move matched displays together**, Cancel putting every changed display back, Cancel before starting writing nothing, a failed restore keeping the window open and naming the display, Quick save keeping a ratio and putting the reference back, Guided sliders never going below the point before, the arrow keys, and why matching can't start. |
| `StatusMenuTests.swift` | 3 | The right-click menu: Refresh Displays, Settings… (⌘,) and Quit Glow (⌘Q), each reaching the menu's own action. Refresh is disabled while displays are being read. Only a right-click or a Control-click opens it, on the press, never a plain, Command or Option click or a release. |
| `SoftwareDimmingTests.swift` | 4 | Gamma scaling per channel, reading the level back from a calibrated table, the 10 % floor, and a table another app changed showing no level instead of a guess. |
| `KeyHoldTests.swift` | 12 | With an injected clock and ticker: a tap is one step with no ramp; after the delay the ramp is 1 % per tick and repeats add nothing; the same pace at any repeat rate; each stop (other key, tap off, range end, pause, macOS taking over, silence, and resuming); a press macOS keeps leaves its repeats and key-up alone; against a real store every target moves 1 % per tick. |
| `KeyWriteTests.swift` | 12 | The coalescer sends the first value at once, drops intermediates while one is in flight, always sends the last and confirms only the last; a value during a read-back takes over; settings are independent; a refused write ends its run. The step and look settings decode when missing or unknown. The overlay model updates in place; the 16-box fill. |
| `LevelBoxTests.swift` | 15 | Box fills at a level (47 % is seven boxes and an eighth 52 % full), the click rule and stepping down from the top lit box, stepping on short ranges, and which box a point hits. |
| `ReadingTests.swift` | 31 | Both reread tiers and the timetable for Off, While open and Always; the pause; skipping a setting being changed, and the funnel leaving a change in flight alone; the 60 s mark; back-off for silent displays; untrusted readings dropped; reads never write; At launch's rules, safe mode and demo exclusions; Patience reaching the hardware profile; uncatalogued codes read once and never writable; Hide and Show per identity, out of the OSD, popover and scenes; the settings decoding. |
| `SetupTests.swift` (rewritten 2026-11-19) | 38 | Step lists that follow the desk: two displays, one, none, safe mode, Mac only, and the step on show staying listed when a display leaves; the tutorial with the same steps, no permission and no open at login. Opening Glow Desk ticks Your displays; a key Glow takes ticks the keys step, and one left to macOS ticks nothing; what a press changes for each key target. One display going straight to the keys, sleeping displays saying matching waits. The rest as below: the main button, Not Now, Save, Cancel, Back and closing restoring every display, the arrow keys, the window rising for patches, the permission watched only on the keys step, open at login, seen on finish and close. |
| `SetupTests.swift` (2026-11-09 to 2026-11-19) | 32 | Step lists for the first run and the tutorial; the main button at each step; one display versus two, Not Now writing nothing, safe mode saying why; Save keeping a Quick calibration as Settings does and turning on move-together; Cancel, Back and closing restoring every display (mock adapter); arrow keys only while comparing; the window rising only for patches on screen; the permission watched only on the finish and noticed within a second; open at login applied only when it differs; seen on finish and close, never by the tutorial; plain words for every display status. |
| `SetupTests.swift` (before 2026-11-09) | 34 | Completion is saved and decoded. First-run and tutorial steps: the permission comes before Try it, and the tutorial shows it only while access is off. Back, finish, closing midway and open at login under `swift run`. The permission step: "Skip for Now", watching only on that step, asking, and noticing the grant within a second. The tour: each stop fires once and is announced once; only the current stop ticks; the overlay stop waits for the switch; every stop has a keyboard way (↑/↓ in the sandbox, ←/→, focus, Space); the checklist goes back and forth; the tour survives Back and Continue; choosing saves the setting and previewing doesn't. The pretend desk: all four control labels, responders per target, key-grid steps, overlays per display, the top end and settings Glow can't control. Try it's reading, none, demo, built-in-only and ready states. |

## Walkthrough (from the off-screen snapshots)

Steps 1–3 below describe the app before 2026-11-09. Since then: setup is the steps in "Setup cut to what teaches, 2026-11-19" above (before that, the four in "Keys, popover, setup and reading"), in a 640 × 600 window; Glow Desk can draw boxes and has rounder buttons; General has Quit Glow and no Wake section; the Glow pane has no Quit; Controls adds Brightness step and Look; Reading is a new pane between Controls and General; Displays adds Reading and Hidden by you sections.

1. **First launch: setup**, an 840 × 600 window. The first run has five steps. Reopened from Settings › General › Open Tutorial…, it shows the tour and Try it, plus the permission step while access is off.
   - **Welcome:** Glow's mark, two display outlines, draws itself in and the two screens ease to the same light. Under Reduce Motion it appears without the move.
   - **Tour, "Learn Glow by doing":** a pretend desk of the three demo displays. It never touches a real display. A checklist of five things to do, each with a pointer way and a keyboard way:
     - press a brightness key (an on-screen sun key, or ↑/↓ while the window is in front);
     - drag a display's slider (or Tab to a setting and press ←/→);
     - point at a setting to see how Glow controls it (Hardware control, Native control, Software dimming, Not available on this connection);
     - choose which displays the keys change, which is saved to Settings › Controls;
     - watch the overlay appear on the display that changed. The "Show overlay on change" switch from Settings › General sits beside the checklist.

     Each stop ticks off once and is announced to VoiceOver. The line under the desk says what each one means.
   - **Permission, "One permission":** says why the brightness keys need Accessibility and what it is never used for. It offers Open System Settings… and Skip for Now, and notices the grant by itself, checking once a second. Under `swift run` it says the grant would go to the terminal app and that Glow.app is the real path.
   - **Try it:** the person's own displays as Glow reads them, read only: each display's brightness and volume, with how Glow controls each. It handles still reading, no displays, demo displays and the built-in display alone. Once access is on, it asks them to press the real brightness keys.
   - **Done:** where to find things and what the brightness keys change (or that they wait for access). "Open Glow at login" is disabled under `swift run` and says why.
2. **Glow Desk** (menu-bar popover), 308 pt wide.
   - The header has the coral Glow mark, "Glow" and "Demo displays" when they aren't the person's own. Under it, the scenes line: "Scenes", then one icon button per scene, the active one lit, and **+** for a new one. When they don't all fit, **…** opens Settings › Scenes (`popover-many-scenes`); with none, just **+** (`popover-no-scenes`). A scene that didn't fully apply says so underneath: "Work: Applied 2; 1 couldn't be updated" (`popover`). A scene that changes input asks first (`confirm-scene`).
   - One row per display: name, how Glow controls it, brightness with a tabular %, and volume when the display has it. The LG says "Dims the picture, not the backlight." A long name ends in an ellipsis (`popover-long-name`).
   - Then the match line, and the brightness keys as four buttons (All, Cursor, Focused, Mac), with a caption when the keys go to macOS or Focused needs naming, and **Allow…** beside it when access is off in the app (`popover-keys-allow`). Last, **More controls…** alone at the trailing edge. Refresh Displays, Settings… and Quit Glow are on a right-click or Control-click of the mark. Other desks: `popover-two`, `popover-two-matched`, `popover-one`, `popover-reading`, `popover-none`, `popover-paused`.
3. **Glow Settings**, a 760 × 600 window with a 168 pt sidebar.
   - **General:** open at login, overlay, demo displays, Refresh Displays, **Wake › Reapply settings after wake** (off), and Open Tutorial….
   - **Displays:** display tiles, then the generated Digital OSD in Essentials, Display and Connectivity sections. Each row shows its status and evidence. Changing input asks first: "Switch your Dell U2723QE to HDMI 1?". The Glow section names the scenes the display is in. **Starting values › Restore Starting Values** is disabled while nothing has changed (`settings-displays-restore`). After a scene, it puts back 68 %, 35 % and sRGB and says "Restored 3 settings" (`settings-displays-restored`).
   - **Brightness Match:** each display is "Reference", "Matched" (with the method and date), "Match is out of date" (with the route it was matched over and the route now) or "Not matched", and a software-dimmed display says matching dims its picture, not its backlight. Then the Quick and Guided methods, **Match Displays…** (disabled with the reason when fewer than two displays can be set), **Move matched displays together** and **Forget Match**.
   - **Match Displays…** opens a 480 × 580 calibration window: choose the reference and method, then match each display's grey with its slider or ←/→ (one point for Quick, five for Guided), review the curves and save. Demo displays get tiles in the window in place of the full-screen patches. Paused, it shows the calm notice and waits.
   - **Scenes:** with demo displays on, a note that these are examples and aren't saved. Each scene shows its symbol, each display's values ("Input HDMI 1 (asks first)"), **Edit…**, **Apply** and a ⋯ menu (Move Up, Move Down, Delete…). The active one is tagged "Active". A result is honest when partial: "Applied 2; 1 couldn't be updated" (`pane-scenes-partial`). With none, a centred empty state and **New Scene from Current Settings** (`pane-scenes-empty`).
   - **Scene editor**, a sheet: name, a row of symbol tiles, then one section per display. Each has **Use Current Values** and a check button per setting, with its value. Input carries an "Asks first" tag. Power is listed but can't be ticked. A caption counts the settings that can't be part of a scene (`scene-editor`, `scene-editor-saved`). A display that's away keeps its saved values, which can only be removed (`scene-editor-away`).
   - **Controls:** Accessibility status, with **Allow…** while it's off. Then the control target, the focused display (only the displays connected now), fine adjustment, and **Preview Overlay**, which says why when it's disabled.
   - **Connection:** every capability, including manufacturer codes, with raw code, evidence, route, access and write reliability. Copy report copies a redacted report.
   - **Glow:** last in the sidebar, under Support, with the app icon as its tile: the coral mark, "Glow", the version, two lines on what Glow is, and **Quit Glow**.
4. **While paused** (displays asleep or reconnecting), a calm notice appears. Every control stays visible, is disabled, and says "Paused". Scene buttons and Restore Starting Values are disabled too.

## Known off-screen snapshot artifacts

These are not bugs:
- In dark mode, plain hosting-view snapshots draw the pane header white. The real-window snapshot draws it correctly.
- Inactive off-screen windows draw switches and accent controls grey.
- Alerts show a generic icon.
- Every popover shot shares the demo store, so the active Work scene and its "couldn't be updated" line also show on desks with fewer or no displays (`popover-two`, `popover-none`, `popover-reading`). In the app, the scenes and the desk come from the same displays.

## Release gate

- Run the VoiceOver and keyboard checks on the test Mac. The real-window checks are done there.
- Verify Glow opening at a real login, and the brightness keys with Accessibility allowed: a tap moves one step, and a held key moves 1 % at a time with the overlay following, then stops at key-up.
- Run `--probe-displays` and `--ddc-selftest` with a real external monitor attached before calling DDC/CI tested. Glow makes a DDC/CI setting editable only after a read on that monitor succeeds, but no monitor has answered one yet. Of ADR 0001's transport decisions, the per-connection profile (7, with the standard profile on every connection so far) and the read-only baseline (9) are built. Alternate addressing (8) isn't.
