import AppKit
import SwiftUI
import XCTest
@testable import Windbar

/// Renders the real UI with fixture devices, for App Store screenshots.
///
/// Screenshots need the app populated with plausible fans, and the real account
/// needs actual hardware bound to it. Rather than add a demo mode to the shipping
/// app, this drives the same dependency injection the other tests use, so the
/// production target gains nothing and ships nothing extra.
///
/// The *interface* rendered here is genuine, which is Apple's requirement. Only
/// the device data is fixture, exactly as `fastlane snapshot` works on iOS.
///
/// Skipped unless WINDBAR_SHOT_DIR is set, so normal and CI test runs ignore it:
///
///   WINDBAR_SHOT_DIR=$PWD/design/screenshots/raw \
///     xcodebuild test -project Windbar.xcodeproj -scheme Windbar \
///       -destination 'platform=macOS' \
///       -only-testing:WindbarTests/ScreenshotHarness
@MainActor
final class ScreenshotHarness: XCTestCase {

    /// Always the sandbox temp directory, never an arbitrary path.
    ///
    /// The host app carries `com.apple.security.app-sandbox`, so the test process
    /// inherits it and writing anywhere else fails with "You don't have permission
    /// to save the file". `design/render_screenshots.sh` reads the printed paths
    /// and copies the results out.
    private func outputDirectory() throws -> URL {
        guard ProcessInfo.processInfo.environment["WINDBAR_SHOT_DIR"] != nil else {
            throw XCTSkip("Set WINDBAR_SHOT_DIR to render App Store screenshots")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("windbar-screenshots", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Room names, not model names. A listing showing "Tower Fan" reads as a demo;
    /// "Bedroom" reads as somebody's actual home, which is what converts.
    private func fixtureDevices() -> [DreoDevice] {
        [
            DreoDevice(
                serialNumber: "WB-DEMO-0001",
                deviceName: "Bedroom",
                model: "DR-HTF004S",
                controlsConf: DeviceTemplateCatalog.schema(forModel: "DR-HTF004S"),
                state: [
                    "connected": .bool(true),
                    "poweron": .bool(true),
                    "windlevel": .int(9),
                    "windtype": .int(1),
                    "shakehorizon": .bool(true),
                    "hoscangle": .int(60),
                    "temperature": .int(74)
                ]
            ),
            DreoDevice(
                serialNumber: "WB-DEMO-0002",
                deviceName: "Office",
                model: "DR-HPF008S",
                controlsConf: DeviceTemplateCatalog.schema(forModel: "DR-HPF008S"),
                state: [
                    "connected": .bool(true),
                    "poweron": .bool(true),
                    "windlevel": .int(3),
                    "windtype": .int(4),
                    "temperature": .int(71)
                ]
            )
        ]
    }

    private func readyModel() async -> AppModel {
        let api = DreoAPIServiceStub()
        await api.setDevicesResult(.success(fixtureDevices()))
        await api.setSession(DreoSession(accessToken: "demo", regionHost: "us"))
        let model = AppModel(
            apiService: api,
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(
                stored: DreoCredentials(email: "demo@windbar.app", password: "demo")
            ),
            settingsRepository: SettingsRepositoryFake()
        )
        await model.start()
        return model
    }

    /// Renders through AppKit rather than SwiftUI's `ImageRenderer`.
    ///
    /// `ImageRenderer` cannot draw AppKit-backed controls: every Toggle came out as
    /// a yellow "prohibited" placeholder, and the popover had no background because
    /// its material normally comes from the window. Hosting the view in a real
    /// `NSHostingView` and calling `cacheDisplay` runs the genuine drawing code, so
    /// switches, sliders and segmented controls all render correctly. It also needs
    /// no Screen Recording permission, unlike capturing the window off the display.
    private func render(_ view: some View, to url: URL, named name: String) throws {
        let hosting = NSHostingView(
            rootView: view
                .tint(Theme.accent)
                .background(Color(nsColor: NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)))
        )
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()

        guard hosting.frame.width > 1, hosting.frame.height > 1 else {
            XCTFail("\(name) laid out to \(hosting.frame.size)"); return
        }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            XCTFail("No bitmap for \(name)"); return
        }
        rep.size = hosting.bounds.size                      // 2x backing on Retina
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode \(name)"); return
        }
        let dest = url.appendingPathComponent(name)
        try png.write(to: dest)
        print("rendered \(dest.path)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }

    func test_renderScreenshots() async throws {
        // outputDirectory() throws XCTSkip when WINDBAR_SHOT_DIR is unset, which is
        // every ordinary test run, local or CI: this harness is meant to be silent
        // then. The canary below only means anything once a render is actually about
        // to happen, so it has to come after that skip, not before it, or a routine
        // `xcodebuild test` would fail on a check that was never rendering anything
        // in the first place.
        let out = try outputDirectory()

        // A canary, not a formality. WindbarTests' own Debug config sets
        // WINDBAR_DONATIONS (so DonationStateTests runs by default), and these
        // renders become the App Store listing, so the donation UI being
        // compiled in here would bake a "Support Windbar" footer row and a
        // debug panel into screenshots uploaded to Apple, the same guideline
        // 3.1.1 risk as the binary itself carrying it. render_screenshots.sh
        // pins SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG on the xcodebuild
        // invocation for exactly this reason. If this fires, that override
        // was removed, or the harness was run without it.
        #if WINDBAR_DONATIONS
        XCTFail(
            "WINDBAR_DONATIONS is compiled into this run. Screenshots rendered now would " +
            "carry the donation UI into the App Store listing. Run with " +
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG on the xcodebuild command, the way " +
            "design/render_screenshots.sh does."
        )
        return
        #endif
        let model = await readyModel()

        XCTAssertEqual(model.devices.count, 2, "fixtures did not load; the rest would render empty")
        XCTAssertFalse(model.devices.contains { $0.controlsConf?.isEmpty ?? true },
                       "no control schema, so speed and mode rows would be missing")

        // Four frames, four genuinely different views. An earlier five-frame cut
        // repeated MenuBarView and SettingsView twice with only the caption changed,
        // which wastes the slots that carry most of the conversion weight.
        try render(MenuBarView(appModel: model), to: out, named: "01.png")   // hero
        try render(SettingsView(appModel: model), to: out, named: "02.png")  // hotkey
        try render(AddDeviceView(appModel: model), to: out, named: "03.png") // pairing

        // Trust frame. Deliberately the real sign-in screen: the app does need a
        // Dreo account, and saying so on the listing beats a one-star review from
        // someone who found out after paying.
        let signedOut = AppModel(
            apiService: DreoAPIServiceStub(),
            socketService: DreoSocketServiceFake(),
            keychainRepository: KeychainRepositoryFake(),
            settingsRepository: SettingsRepositoryFake()
        )
        await signedOut.start()
        XCTAssertEqual(signedOut.launchState, .needsLogin, "frame 04 needs the sign-in view")
        try render(MenuBarView(appModel: signedOut), to: out, named: "04.png")
    }
}
