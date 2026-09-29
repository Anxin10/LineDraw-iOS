# LineDraw local MIT dependency changes

Upstream: https://github.com/jkcoxson/idevice
Revision: d32c8189c51c2789496b0768039419c3705498c3 (0.1.68).
Upstream code and these small modifications remain under LICENSE.txt (MIT).

- Add XCUITestService::run_rsd for an existing authenticated tunnel, sharing the
  unchanged XCTest lifecycle implementation with the original provider path.
- Remove the upstream debug statement that prints the full Remote Pairing plist.

No StikDebug, StikPair, or TouchSynthesis code is incorporated.
- Own the HTTP connect host string so the Cryptex TSS future is Send under the on-device Tokio runtime.
- Open the advertised Cryptex service directly in the mount helpers to avoid the generic RsdService future lifetime inference issue; the same RemoteXPC handshake is retained.
