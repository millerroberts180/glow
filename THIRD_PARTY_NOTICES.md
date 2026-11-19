# Third-party notices

A copy of this file is inside Glow.app, at `Contents/Resources/THIRD_PARTY_NOTICES.md`.

## MonitorControl

Glow's DDC/CI path on Apple silicon adapts MonitorControl's approach (commit `7cfe645`, https://github.com/MonitorControl/MonitorControl):

- **Matching displays to services.** Each `CGDirectDisplayID` is paired with an IORegistry `DCPAVServiceProxy` by scoring the framebuffer location, the EDID UUID fields, and the vendor, product, serial number and name, then assigning from the best score down so no service serves two displays (`Support/Arm64DDC.swift`). Glow's version is `DDCServiceMatcher` in `Sources/GlowApp/Hardware/DDCServiceMatching.swift`.
- **EDID UUID fields.** The byte offsets of the vendor, product, manufacture date and image size inside the `EDID UUID` string that CoreDisplay attaches to each service (`Arm64DDC.swift`). Glow reads them in `DDCServiceCandidate`.
- **Timing.** Waits of 10 ms before a write, 50 ms before a read and 20 ms between retries, and 4 retries (`Arm64DDC.swift`). Glow's defaults are `DDCTransportProfile.standard` in `Sources/GlowApp/Hardware/DDCPacket.swift`.

```
MIT License

Copyright © 2017

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
