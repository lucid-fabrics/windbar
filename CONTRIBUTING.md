# Contributing

Notes for anyone working on Windbar, including future me.

## Setup

The `.xcodeproj` is generated from `project.yml` and gitignored, so generate it after cloning:

```bash
brew install xcodegen
git clone git@github.com:lucid-fabrics/windbar.git
cd windbar
xcodegen generate
open Windbar.xcodeproj
```

Press Cmd-R. The app appears in the menu bar, not the Dock. If the project fails to open or looks
stale after a pull, run `xcodegen generate` again.

## Commands

| Task | Command |
|------|---------|
| Regenerate the project | `xcodegen generate` |
| Build | `xcodebuild build -project Windbar.xcodeproj -scheme Windbar -configuration Debug` |
| Test | `xcodebuild test -project Windbar.xcodeproj -scheme Windbar -configuration Debug` |
| One test class | `xcodebuild test -project Windbar.xcodeproj -scheme Windbar -only-testing WindbarTests/AppModelTests` |
| Lint | `swiftlint lint --quiet` |
| Build and relaunch | `scripts/demo.sh` |

Check Release as well as Debug before shipping. Whole-module optimisation surfaces warnings Debug
hides, and it has caught real problems here more than once.

## Releasing

Windbar ships as a notarized DMG on GitHub Releases, and installed copies update themselves from the
`appcast.xml` attached to the newest release. Releasing is a merge, not a command:

1. Bump `MARKETING_VERSION` in `project.yml`.
2. Add `docs/release-notes/<version>.md`. Its text becomes the release description.
3. Open a PR and merge it.

On the push to `main`, `.github/workflows/release.yml` sees the version moved and the `v<version>`
tag missing, runs `fastlane mac release_dmg` (build, sign with Developer ID, notarize, staple, make
the DMG, sign the appcast), then creates the GitHub release with `Windbar-<version>.dmg` and
`appcast.xml`. A merge that leaves the version alone releases nothing. To rebuild a version that
already has a tag, run the Release workflow by hand from `main`; it replaces the assets in place.

Never change `SU_PUBLIC_ED_KEY` in `project.yml`. Every installed copy verifies updates against it,
so changing it strands all of them.

The release workflow needs six repository secrets (Settings > Secrets and variables > Actions).
They are only ever given to the Release workflow, never to pull requests:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate and key, `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Password the `.p12` was exported with |
| `ASC_KEY_ID` | App Store Connect API key id, used only for notarization |
| `ASC_ISSUER_ID` | Issuer id of that key |
| `ASC_KEY_P8` | Contents of the key's `.p8` file |
| `SPARKLE_ED_PRIVATE_KEY` | Private half of the Sparkle update key, signs the appcast |

## Layout

```
Windbar/
├── App/           AppModel (single source of truth), entry point
├── Models/        Data types, BLE/ (CBOR codec, message builders), API/, Errors/
├── Services/      REST, WebSocket and BLE clients, Protocols/
├── Repositories/  Keychain and UserDefaults, Protocols/
└── Views/         MenuBar/, Settings/, Setup/, AddDevice/
```

One type per file, named after the type. Protocols live in a `Protocols/` subdirectory. Error types
are suffixed `Error`.

## Conventions

**Concurrency.** Swift 6 strict concurrency is on. `@MainActor @Observable` for app state and views,
`actor` for anything doing I/O, `async`/`await` throughout with no completion handlers and no
Combine. Mark non-observable dependencies `@ObservationIgnored`. Cancel an in-flight `Task` before
starting its replacement.

CoreBluetooth is the deliberate exception. Its delegates are not `Sendable` and its callbacks are
nonisolated by contract, so `DreoBLEPairingService` is not actor-isolated at all. It relies on
`queue: .main` to serialise everything instead, which is why its state is `nonisolated(unsafe)`.
That is an accurate description of the guarantee, not a way around the checker.

**Dependencies.** Constructor injection against a protocol, with a real default:

```swift
init(
    apiService: DreoAPIServiceProtocol = DreoAPIService(),
    keychainRepository: KeychainRepositoryProtocol = KeychainRepository()
) { }
```

System frameworks only, with one exception: `KeyboardShortcuts` (SPM, MIT) for the global hotkey.

**Tests.** XCTest with hand-written stubs and fakes in `TestDoubles/`, no mocking framework. Nothing
touches the real network or the real Keychain; everything goes through a protocol. Put `@MainActor`
on tests whose subject is main-actor isolated.

**Commits.** `type(scope): description`, where type is one of `feat`, `fix`, `refactor`, `docs`,
`test`, `chore`.

## Things worth knowing before you change them

**Decoding is deliberately forgiving.** The device list and each device's control schema decode item
by item and drop only what they cannot parse. This is not defensive habit: a single device returning
an unfamiliar shape used to fail the whole response and leave the app showing nothing. Keep it lossy.

**Bundled resources are generated, not written.** `DeviceTemplates.json` (control layouts for 84
models) and `Labels.json` (English strings for the localisation keys older devices return) are both
extracted from the vendor app's own assets. If a model is missing or a label reads wrong, regenerate
rather than hand-editing.

**BLE message order matters.** The fan rejects a WiFi join unless the session opens the way the
official app opens it. See the protocol notes in the README.

**Map key order matters.** The CBOR encoder preserves insertion order because the wire format
depends on it, which is why `CBORValue.map` holds pairs rather than a dictionary.

## Security

Credentials live in the Keychain (service `com.lucidfabrics.windbar.credentials`) and are never written to disk
or logged. Do not commit `*.p12`, `*.mobileprovision`, real credentials, `xcuserdata/`,
`DerivedData/` or `build/`. Test fixtures use placeholder networks and passwords; keep it that way.
