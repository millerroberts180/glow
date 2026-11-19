# Releasing Glow

Glow is distributed from its own site, not the Mac App Store. The App Store accepts only public
APIs (App Review Guideline 2.5.1), and Glow's display control goes through private ones: DisplayServices,
a CoreDisplay symbol and IOKit's IOAVService calls (see "The hardened runtime needs no exceptions"). A
release is a DMG holding Glow.app, a link to /Applications and the EULA. The app and the DMG are both
signed with a Developer ID, notarized by Apple and stapled, so Gatekeeper opens them without a warning,
offline too. A release is built for Apple silicon only (arm64; see "Apple silicon only"), and Glow has no
update mechanism yet. It has no trial or license key, and never connects to the network.

`scripts/release.sh` does all of it. Until the Apple Developer account exists, `scripts/release.sh
--unsigned` makes a test DMG, so the packaging can be checked now. That test DMG is also what people
download until then (see "A test DMG, before the account exists").

## Where things are set

| What | Where |
| --- | --- |
| Version people see (`CFBundleShortVersionString`) | `VERSION`, or the script's argument |
| Build number (`CFBundleVersion`) | Worked out by the script; see below |
| Bundle ID, copyright holder, website, support, privacy policy and EULA links | `Resources/release.env`, the one place they are set |
| Everything else in the bundle's Info.plist | `Resources/Info.plist` |
| The app icon | `Resources/AppIcon.icns`, made by `scripts/make-icon.sh` |
| The license shipped in the DMG | `docs/legal/EULA.txt` |
| Signing certificate and notarization credentials | `DEVELOPER_ID` and `NOTARY_PROFILE` in the environment, never in the repository |

`scripts/bundle.sh` stamps the bundle ID, copyright and links from `Resources/release.env` on the
bundle's copy of Info.plist, and `scripts/release.sh` builds through it, so local builds and releases
carry the same identity. A website, privacy policy or EULA link left empty there keeps the source
plist's placeholder on `glow.example`, so a test build still points somewhere. Settings › Glow (About)
reads the links from the bundle (`ReleaseInfo.swift`), and Glow opens one only when someone clicks it.
The privacy policy, EULA and support links point to GitHub: the first two to `docs/legal/` on `main`,
and support to the repository's issues.

Support is an email address (`SUPPORT_EMAIL`, stamped as `GlowSupportEmail`), a help page
(`SUPPORT_URL`, stamped as `GlowSupportURL`), or both. The Support link in Settings › Glow opens the
page when there is one, and otherwise an email. It shows the address when there is one, otherwise the
page's host (`github.com`), as the Website link shows its host. The source plist has no support address,
so an empty `SUPPORT_EMAIL` stays empty; only with neither set does About fall back to
`support@glow.example` (`ReleaseInfo.swift`). I set only `SUPPORT_URL`, so Glow publishes no email
address. `scripts/release.sh` refuses a signed release while the website, privacy policy or EULA link
is empty, or both support settings are. The source plist keeps the bundle ID and copyright only so it
is complete on its own, and its version (0.1.0, build 1) is a placeholder that only a release replaces.

**The build number** is the UTC date, the UTC time and the git commit count, such as
`20261110.23701.4` (2026-11-10 at 02:37:01 UTC, 4 commits). It starts with the date and time so it
rises with every build, whatever happens to the history (a squash or a rebase can lower a commit
count), and UTC never steps back for daylight saving. The count says roughly which commit a build came
from. Each part is a plain integer well under 2³¹, the form Apple asks for, so leading zeros of the
time are dropped (02:37:01 is 23701).

## One-time setup

Once these are done, nothing else is needed for a signed release.

1. **Join the Apple Developer Program** at <https://developer.apple.com/programs/enroll/> (paid yearly).
   - Enrolling as an individual puts your own legal name on the certificate, and macOS shows it as
     Glow's developer.
   - Enrolling as an organization shows the company's name instead. It needs a legal entity and a
     D-U-N-S number, and takes longer.
2. **Create a Developer ID Application certificate.** Only the account holder can create one.
   1. In Keychain Access, choose Keychain Access › Certificate Assistant › Request a Certificate From a
      Certificate Authority. Enter your email and name, choose "Saved to disk", and save the request.
      Its private key stays in your login keychain.
   2. At <https://developer.apple.com/account/resources/certificates>, add a certificate, choose
      **Developer ID Application**, keep the default (G2 Sub-CA) authority, and upload the request.
   3. Download the certificate and double-click it to add it to the login keychain.
   4. Check that it's there: `security find-identity -v -p codesigning` lists
      `"Developer ID Application: Your Name (TEAMID)"`.
   5. Back it up: in Keychain Access, export the certificate with its private key as a `.p12`, with a
      strong password, somewhere safe outside the repository (`.gitignore` excludes `*.p12`). Apple
      allows only a few Developer ID certificates per account, and a lost key can't be recovered.
3. **Save notarization credentials** in the keychain, under a profile name the script uses:
   1. Create an app-specific password at <https://account.apple.com> › Sign-In and Security ›
      App-Specific Passwords.
   2. Find your Team ID under Membership details at <https://developer.apple.com/account>.
   3. Run this, and paste the app-specific password when it asks:

      ```sh
      xcrun notarytool store-credentials glow-notary --apple-id you@example.com --team-id TEAMID
      ```

      An App Store Connect API key works too (`--key AuthKey_XXXX.p8 --key-id … --issuer …`). It suits a
      build server better. Keep the `.p8` out of the repository (`.gitignore` excludes `*.p8`).
4. **Tell the script about them**, in your shell profile or before each release:

   ```sh
   export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
   export NOTARY_PROFILE=glow-notary
   ```

   `DEVELOPER_ID` may also be the certificate's SHA-1 hash, as `security find-identity` prints it.

The Command Line Tools include `notarytool` and `stapler`; Xcode isn't needed for any of this.

To try permissions with a Developer ID signature before a release,
`GLOW_SIGN_IDENTITY="$DEVELOPER_ID" scripts/bundle.sh` signs `build/Glow.app` with it. That build isn't
notarized, so copy it to another Mac without a download, or open it on this one.

## Cutting a release

1. Before the first release, settle the launch checklist below. The script refuses a signed build while
   the bundle ID in `Resources/release.env` contains "prototype" (in any case), or while the website,
   privacy policy or EULA link there is still empty, or both `SUPPORT_EMAIL` and `SUPPORT_URL` are.
2. Set the version in `VERSION` (three numbers, such as `1.0.1`), or pass it as the argument.
3. Commit everything. The script warns if the tree has uncommitted changes, since the release then
   matches no commit.
4. Run the tests: `scripts/test.sh`.
5. Build, sign and notarize:

   ```sh
   scripts/release.sh          # the version from VERSION
   scripts/release.sh 1.0.1    # or a version given here
   ```

   This checks the certificate and the notary profile before it builds, so a missing piece fails at
   once. Without `DEVELOPER_ID` or `NOTARY_PROFILE`, it lists everything still missing in one message,
   with the setup steps. Notarization runs twice, once for the app and once for the DMG, and usually
   takes a few minutes each. If Apple rejects either, the script prints Apple's log of what was wrong
   and stops.
6. It leaves `dist/Glow-<version>.dmg`, `dist/Glow-<version>.dmg.sha256` and
   `dist/Glow-<version>.dSYM.zip`, the debug symbols (`dist/` isn't committed). Keep the symbols for as
   long as anyone uses that version: they are the only way to read its crash reports (see "Reading crash
   reports"). They never go in the DMG or on the site.
7. Try the DMG as someone new to Glow would. Download it from the site to a Mac with Apple silicon that has never run
   Glow, so it arrives quarantined. Open it, drag Glow to Applications and open Glow: macOS should show
   only its ordinary "downloaded from the internet" question, naming the developer.
8. Upload the DMG and its checksum to the site, then tag the commit: `git tag v1.0.1`.

What the script does, in order:

1. `GLOW_ARCHS=arm64 scripts/bundle.sh <app> <dSYM>`, with both paths in a temporary folder, so the
   bundle is assembled exactly as a local build is: `swift build -c release --triple
   arm64-apple-macosx14.0 --scratch-path .build-bundle/arm64`, the plist stamped from
   `Resources/release.env`, then `dsymutil` gathers the debug symbols into a dSYM before `strip -x`
   removes them from the binary. `build/Glow.app` is never touched. bundle.sh signs the bundle so it
   launches, with "Glow Local Signing" or ad hoc (the script clears `GLOW_SIGN_IDENTITY` for this step);
   that signature is replaced in step 3. The script checks that the binary is arm64 only, and that the
   binary and the dSYM have the same UUID (`dwarfdump --uuid`).
2. Stamps the bundle's copy of Info.plist with the version and the build number, using
   `plutil -replace <key> -string <value>`, which takes each value as one argument, so a quote or
   apostrophe stays as it is. bundle.sh stamps the bundle ID, copyright and links the same way.
3. Signs the app: `codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID"`, with no
   entitlements file (see below), and checks that the hardened runtime is on. A test DMG is signed
   differently (see "A test DMG, before the account exists").
4. Zips the app with `ditto -c -k --keepParent`, notarizes it with
   `xcrun notarytool submit --keychain-profile "$NOTARY_PROFILE" --wait`, and staples the ticket to the
   app with `xcrun stapler staple`.
5. Makes the DMG with `hdiutil` (LZMA-compressed, volume name "Glow"): the app, an `/Applications` link
   and `EULA.txt`. It then signs, notarizes and staples the DMG too.
6. Mounts the DMG out of sight of Finder and checks what ships: `codesign --verify --deep --strict`,
   arm64 only, the bundle ID and version in its Info.plist, the link and the EULA, and
   `spctl --assess --type execute -vv` for the app. After detaching it,
   `spctl --assess --type open --context context:primary-signature -vv` checks the DMG.
7. Writes the SHA-256 checksum beside the DMG in `dist/`, and zips the dSYM there too
   (`ditto -c -k --keepParent`), named after the DMG.

### A test DMG, before the account exists

```sh
scripts/release.sh --unsigned
```

This makes `dist/Glow-<version>-unsigned.dmg` without any Apple account. The app is signed under the
hardened runtime, so it runs as a signed build will: with "Glow Local Signing" when
`scripts/signing-identity.sh` has made it, as `scripts/bundle.sh` signs (it unlocks
`~/Library/Keychains/glow-signing.keychain-db` and passes `--keychain`), and otherwise ad hoc. The
script prints which. Nothing is notarized, so the Gatekeeper checks are skipped, and Gatekeeper refuses
the DMG once it has been downloaded. To try it on a test Mac, open it from System Settings › Privacy &
Security › Open Anyway, or copy it over without a download. Placeholder links are allowed in it; the
script says so at the end.

Until there is a Developer ID, the downloadable test DMG is signed with "Glow Local Signing", so the
Accessibility grant survives updates. macOS ties the grant to the signature. Until 2026-11-19 I signed
the download ad hoc, and an ad-hoc signature changes with every build, so each update needed the grant
given again. Every build signed with this one certificate has the same designated requirement
(`codesign -d -r-` shows `certificate leaf = H"…"`), so macOS treats each update as the same app. The
first Developer ID release will have a new requirement, so everyone grants Accessibility once more
then.

Back up the identity's private key: a new certificate means everyone grants Accessibility once more.
In Keychain Access, export "Glow Local Signing" (in the `glow-signing` keychain) with its private key as
a `.p12`, with a strong password, somewhere safe outside the repository (`.gitignore` excludes
`*.p12`). `scripts/signing-identity.sh` makes a new certificate on any Mac whose `glow-signing` keychain
doesn't already hold one.

## Apple silicon only

Local builds (`scripts/bundle.sh`) are universal, so Glow can be tried on an Intel Mac. A release is
arm64 only, because Glow does much less on an Intel Mac:

- **No DDC/CI.** Glow talks to external monitors through IOAVService (`IOAVTransport.swift`), Apple
  silicon's way to a display's I2C bus. It finds them by walking the IORegistry for Apple silicon's
  display services: an `AppleCLCD2` or `IOMobileFramebufferShim` framebuffer with an external
  `DCPAVServiceProxy` under it (`DDCServiceMatching.swift`). An Intel Mac has neither. Its monitors are
  reached through IOFramebuffer's I2C calls instead (`IOFBCopyI2CInterfaceForBus`, `IOI2CSendRequest`),
  which Glow doesn't build (`DDCControl.swift`, and "Not built yet" in `docs/development.md`). So on an
  Intel Mac every external monitor would get software dimming only: no hardware brightness, contrast,
  volume or input.
- **What would still work:** software dimming, through public CoreGraphics calls, and probably the
  built-in display and Apple displays, through DisplayServices, which Intel Macs also have. Glow hasn't
  been run on an Intel Mac, so that is untested.

Glow on an Intel Mac could only dim external monitors in software, and macOS 26 is the last macOS for
Intel Macs. So the site should say Glow needs a Mac with Apple silicon. An Intel Mac
won't open an arm64-only app: macOS says it isn't supported on this type of Mac.

To support Intel Macs later: build the IOFramebuffer DDC path and test it on an Intel Mac, then make
`scripts/release.sh` build universal (drop `GLOW_ARCHS=arm64` from its bundle.sh call and change its two
arm64 checks). The dSYM then covers both slices; `atos -arch x86_64` reads the Intel one.

## Reading crash reports

The release binary is stripped (`strip -x`), and Glow is one module, so almost every function is a local
symbol: `strip -x` leaves 3 of the 8,238 function symbols in the arm64 build. A crash report from
someone's Mac shows addresses, not function names. The dSYM zipped beside the DMG turns them back into names,
files and lines, but only for the exact build it came from. In the 0.1.0 test DMG, for instance, `atos`
gives one address back as `Glow + 8` from the binary alone, and as a function at
`SoftwareDimmer.swift:131` from the dSYM.

1. Unzip `Glow-<version>.dSYM.zip`. Check that it matches the report: `dwarfdump --uuid Glow.app.dSYM`
   prints a UUID that must equal the one on the `Glow` line of the report's Binary Images (in a `.ips`
   file, the `uuid` of the image named Glow).
2. For one address, use `atos` with the load address from that Binary Images line:

   ```sh
   atos -arch arm64 -o Glow.app.dSYM/Contents/Resources/DWARF/Glow -l 0x100c34000 0x100c5a1f4 0x100c4b880
   ```

3. For a whole report, `symbolicatecrash` finds the dSYM by its UUID through Spotlight, once it is
   unzipped somewhere Spotlight indexes, such as a folder in your home:

   ```sh
   export DEVELOPER_DIR=$(xcode-select -p)
   "$(xcode-select -p)/../SharedFrameworks/DVTFoundation.framework/Versions/A/Resources/symbolicatecrash" report.crash > symbolicated.crash
   ```

   `symbolicatecrash` ships with Xcode, not the Command Line Tools, and reads the older `.crash` text
   form. For a `.ips` report, open it in Console (which shows the text form) and save that, or use
   `atos` per frame. This step hasn't been tried yet: the Mac Glow is built on has only the Command
   Line Tools. `atos` and `dwarfdump` come with those.

## The hardened runtime needs no exceptions

Notarization requires the hardened runtime. Each exception it allows was checked against the code in
`Sources/GlowApp` and the release binary; none is needed, so there is no entitlements file. Local
builds have always been signed with the hardened runtime (`scripts/bundle.sh` passes `--options runtime`
for every signature, ad hoc included), so a local `build/Glow.app` already runs under it.

- **JIT and unsigned executable memory:** none. Glow is compiled Swift, with no JavaScriptCore, WebKit
  or code generation.
- **Library validation:** `otool -L` shows the binary links only system frameworks (AppKit,
  ApplicationServices, CoreFoundation, CoreGraphics, CryptoKit, Foundation, IOKit, Security,
  ServiceManagement, SwiftUI) and `/usr/lib` and `/usr/lib/swift`. At run time Glow also opens three
  of Apple's own frameworks with `dlopen` and looks up private symbols in them with `dlsym`:
  - `/System/Library/PrivateFrameworks/DisplayServices.framework`, for `DisplayServicesGetBrightness`,
    `DisplayServicesSetBrightness` and `DisplayServicesCanChangeBrightness`: the built-in display's and
    Apple displays' brightness (`NativeBrightness.swift`);
  - `/System/Library/Frameworks/CoreDisplay.framework`, for `CoreDisplay_DisplayCreateInfoDictionary`,
    to match a display to its DDC service (`DDCServiceMatching.swift`);
  - `IOKit.framework`, for `IOAVServiceCreateWithService`, `IOAVServiceReadI2C` and
    `IOAVServiceWriteI2C`: DDC/CI on Apple silicon (`IOAVTransport.swift`).

  These are Apple-signed platform libraries, which library validation always allows. The
  `disable-library-validation` exception is for code signed by another team, and Glow loads none. A
  private symbol isn't a matter for the hardened runtime or notarization either: the notary service
  checks the signature and scans for malware, and it is App Review that rejects private API use.

  A probe making the same `dlopen` and `dlsym` calls, signed ad hoc with `--options runtime`, loaded all
  three, resolved all nine symbols, and read the built-in display's brightness, CoreDisplay's dictionary
  and the gamma table. No external monitor was connected when it ran, so it opened no IOAVService.
  Whether DDC/CI works under the hardened runtime therefore rests on `build/Glow.app` changing a
  monitor, since it is signed the same way, and on the first signed build (launch checklist).
- **DYLD environment variables:** not used.
- **Debugging other processes:** none. No task ports, `ptrace` or other processes' memory.
- **Apple Events:** none are sent (no `NSAppleScript`, `OSAScript`, Apple Event descriptors or Scripting
  Bridge), so neither the `com.apple.security.automation.apple-events` entitlement nor
  `NSAppleEventsUsageDescription` is needed.
- **Network:** none. There is no `URLSession`, Network framework, socket or WebKit, in the code or in the
  binary's imported symbols (`nm -u`). The only URLs are the release links, opened in the browser or
  mail app only when clicked, and the System Settings link for Accessibility. A network entitlement
  would only matter under the App Sandbox anyway.
- **Camera, microphone, location, contacts, calendars, photos:** not used. Volume is the monitor's own
  speaker volume, set over DDC/CI; Glow doesn't use Core Audio.
- **The event tap:** one active tap (`.defaultTap`) at the session level (`.cgSessionEventTap`,
  `.headInsertEventTap`), for `NX_SYSDEFINED` events only (type 14), the kind that carries the
  keyboard's special keys (`BrightnessKeyTap.swift`). It acts on the brightness keys (media-key subtype
  8, key codes 2 and 3) and swallows the presses it takes; every other event passes on unchanged. It
  posts no events (no `CGEventPost`). It is armed only while `AXIsProcessTrusted()` is true
  (`KeyAccess.swift`). An active tap is covered by the Accessibility permission, a TCC grant the person
  gives, not an entitlement. Input Monitoring is for listen-only taps on keyboard events, and Glow's tap
  isn't listen-only and Glow never calls `CGRequestListenEventAccess`, so there should be no Input
  Monitoring prompt. Only a signed build on a clean Mac can confirm the prompts (launch checklist).
- **Software dimming:** `CGSetDisplayTransferByTable`, `CGGetDisplayTransferByTable` and
  `CGDisplayRestoreColorSyncSettings` (`SoftwareDimmer.swift`) are public CoreGraphics calls that need no
  permission.
- **The IORegistry:** reading the device tree's product name, walking the service plane and reading
  display properties (`DDCServiceMatching.swift`) need no entitlement outside the App Sandbox.
- **Screen Recording:** not needed. Glow reads no window contents or pixels; the overlay and Brightness
  Match's patches are Glow's own windows.
- **Other system services:** the login item (`SMAppService.mainApp`), sleep and wake notifications
  (`NSWorkspace`) and key monitors in Glow's own windows (`NSEvent.addLocalMonitorForEvents`) need no
  entitlement.
- **The trial's leftovers:** at launch Glow deletes the "Glow trial" item earlier builds kept in the
  login keychain (`SecItemDelete`, without `kSecUseDataProtectionKeychain`), which needs no
  keychain-access-groups entitlement. The keychain never asks the person: it quietly refuses a delete by
  a build that didn't make the item.
- **No `get-task-allow`:** `codesign -d --entitlements -` on the app in the test DMG prints nothing, so
  it carries none of the debugging entitlement notarization rejects.

SwiftPM also leaves `LC_RPATH`s in the binary: `/usr/lib/swift`, `@loader_path` and the Command Line
Tools' Swift libraries. Nothing loads through `@rpath`, so they do nothing on anyone else's Mac.

This was checked by reading the code and the binary, and with the probe above. Glow hasn't yet been
signed with a Developer ID, so the Accessibility prompt for that signature, DDC/CI from a notarized
build and Open at login are still to be tried on the first signed build before it's released.

## Info.plist choices

- **Usage strings:** none. Accessibility has no usage string (macOS words that prompt itself), and
  Glow uses no Apple Events, camera, microphone, Screen Recording or Input Monitoring.
- **`LSUIElement`:** true. Glow is a menu-bar app with no Dock icon.
- **`LSMultipleInstancesProhibited`:** true. Two copies would both drive the same displays and keys.
- **`LSMinimumSystemVersion`:** 14.0, matching the `arm64-apple-macosx14.0` triple bundle.sh builds for.
- **Sudden termination:** not declared. As it quits, Glow writes pending settings
  (`GlowSettingsStore.flush`) and lifts software dimming, and sudden termination would skip both.
- **Category:** not set yet. `LSApplicationCategoryType` `public.app-category.utilities` would fit a
  tool that controls hardware; Finder's Group By Application Category uses it.
- **`LSArchitecturePriority`:** not set. It only orders the slices of a universal binary, and a release
  has one.
- **`NSHumanReadableCopyright`:** "© 2026 Miller Roberts", stamped from `Resources/release.env`.

## Changing the bundle ID

It is `com.millerroberts.Glow`, set once in `Resources/release.env`. macOS knows an app by its bundle ID,
so anyone already running a build with another one finds:

- **Accessibility granted again,** for the brightness keys: the grant belongs to the old ID.
- **Settings back to their defaults,** and setup runs again. Glow keeps everything it remembers as one
  JSON value, `settings.v1`, in macOS's preferences for its bundle ID (`GlowSettingsStore` in
  `Sources/GlowApp/Settings/GlowSettings.swift`, through `UserDefaults.standard`). That includes the
  scenes, the Brightness Match curves, the values last set on each display, the settings hidden on a
  display and whether setup was completed. A one-time import from the old ID could be added if testers
  should keep them: read `settings.v1` from `UserDefaults(suiteName: "<old ID>")`.
- **Open at login** turned on again in Settings › General: the login item registered belongs to the old
  ID.
- **Nothing else to carry over:** Glow keeps no files of its own, so there is no Application Support
  folder to move. Monitors keep the settings they have.

Local builds take the same bundle ID as releases. On a Mac that runs both, they share settings, and
the Accessibility grant goes to whichever signature last asked, so run one at
a time.

## Launch checklist

Still open before Glow is released:

- [ ] **The bundle ID, confirmed final:** `com.millerroberts.Glow` in `Resources/release.env`, ideally on
  a domain I control. A change after testers have Glow costs them their settings and their
  Accessibility grant (see above).
- [ ] **The support contact in the EULA and the privacy policy,** which still say `[Support email]`.
  About's Support link goes to the GitHub issues (`SUPPORT_URL`), and `SUPPORT_EMAIL` stays empty, so
  Glow publishes no email address.
- [ ] **The privacy policy URL in the EULA,** once `docs/legal/privacy-policy.md` is reviewed.
  `Resources/release.env` already points to it on GitHub.
- [ ] **A trademark search for "Glow" in software** (Nice class 9), at least in the US, the EU and the UK,
  before the name is printed anywhere that's hard to change. "Glow" is a common word and other apps
  already go by it, so this matters more than usual.
- [ ] **Say "Apple silicon" on the site,** with macOS 14 or later: a release is arm64 only (see "Apple
  silicon only").
- [ ] **Testing on macOS 14, 15 and 26, and the current release, with real monitors,** using the signed,
  notarized DMG downloaded from the site: Gatekeeper's first open; the Accessibility prompt, the
  brightness keys, and that no Input Monitoring prompt appears; DDC/CI over DisplayPort, HDMI and
  USB-C, and through a dock; the built-in display and an Apple display; software dimming; and Open at login.
  The Mac Glow has been built and run on so far has macOS 15.7.4.
- [ ] **An Icon Composer icon for macOS 26 and later.** It needs Xcode's `actool`, which the Command Line
  Tools don't include, so `Resources/AppIcon.icns` stays until then.
- [ ] **`LSApplicationCategoryType`** in `Resources/Info.plist` (see "Info.plist choices").
- [ ] **Legal review** of `docs/legal/EULA.txt` and `docs/legal/privacy-policy.md`, filling in their
  placeholders: the legal name or business, address, jurisdiction and liability cap, and the wording of
  what Glow does to displays (sections 4 and 8).
- [ ] **Enrollment as an individual or an organization,** since it decides whose name macOS shows as
  Glow's developer (see "One-time setup").
