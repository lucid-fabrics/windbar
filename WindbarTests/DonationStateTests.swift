#if WINDBAR_DONATIONS
import XCTest
@testable import Windbar

/// The donation gate decides whether the app feels respectful or grabby, and every
/// bound is a judgement call that is easy to break later by "just lowering it a
/// bit". These tests pin each one.
final class DonationStateTests: XCTestCase {

    private let day = 86_400.0

    /// Fully-earned state: long enough installed, used enough, across enough days.
    private func earned(now: Date) -> DonationState {
        var state = DonationState()
        state.firstLaunch = now.addingTimeInterval(-30 * day)
        for offset in 0..<10 {
            for _ in 0..<6 {
                state.recordUse(now: now.addingTimeInterval(-Double(offset) * day))
            }
        }
        return state
    }

    func test_freshInstall_neverPrompts() {
        var state = DonationState()
        state.recordUse()
        XCTAssertFalse(state.shouldPrompt(), "a brand new user must never be asked")
    }

    func test_heavyUseButTooRecent_doesNotPrompt() {
        let now = Date()
        var state = DonationState()
        state.firstLaunch = now.addingTimeInterval(-3 * day)
        for offset in 0..<3 {
            for _ in 0..<40 { state.recordUse(now: now.addingTimeInterval(-Double(offset) * day)) }
        }
        XCTAssertGreaterThanOrEqual(state.toggleCount, Donations.minimumToggles)
        XCTAssertFalse(state.shouldPrompt(now: now),
                       "120 toggles in 3 days is enthusiasm, not an earned ask")
    }

    func test_installedLongEnoughButBarelyUsed_doesNotPrompt() {
        let now = Date()
        var state = DonationState()
        state.firstLaunch = now.addingTimeInterval(-200 * day)
        state.recordUse(now: now)
        XCTAssertFalse(state.shouldPrompt(now: now), "age alone must not earn the ask")
    }

    /// The case that motivates tracking distinct days at all.
    func test_manyTogglesOnOneDay_doesNotPrompt() {
        let now = Date()
        var state = DonationState()
        state.firstLaunch = now.addingTimeInterval(-60 * day)
        for _ in 0..<500 { state.recordUse(now: now) }
        XCTAssertEqual(state.activeDays.count, 1)
        XCTAssertFalse(state.shouldPrompt(now: now),
                       "500 toggles in one sitting is one day of use, not seven")
    }

    func test_earnedUsage_prompts() {
        let now = Date()
        XCTAssertTrue(earned(now: now).shouldPrompt(now: now))
    }

    func test_withinCooldown_doesNotPromptAgain() {
        let now = Date()
        var state = earned(now: now)
        state.recordPrompt(now: now.addingTimeInterval(-10 * day))
        XCTAssertFalse(state.shouldPrompt(now: now), "10 days after asking is far too soon")
    }

    func test_afterCooldown_promptsAgain() {
        let now = Date()
        var state = earned(now: now)
        state.recordPrompt(now: now.addingTimeInterval(-Double(Donations.cooldownDays + 1) * day))
        XCTAssertTrue(state.shouldPrompt(now: now))
    }

    func test_lifetimeCap_isHonoured() {
        let now = Date()
        var state = earned(now: now)
        for index in 0..<Donations.maximumLifetimePrompts {
            state.recordPrompt(now: now.addingTimeInterval(-Double(500 - index * 130) * day))
        }
        XCTAssertEqual(state.promptCount, Donations.maximumLifetimePrompts)
        XCTAssertFalse(state.shouldPrompt(now: now), "must go quiet forever after the cap")
    }

    func test_optOut_isPermanent() {
        let now = Date()
        var state = earned(now: now)
        state.optedOut = true
        XCTAssertFalse(state.shouldPrompt(now: now), "\"No thanks\" has to mean never again")
    }

    /// Earning the ask and being able to show it are separate. Until the Stripe
    /// links exist, canPrompt must stay false however earned the user is, so the UI
    /// never renders buttons that go nowhere.
    func test_canPrompt_requiresConfiguredLinks() {
        let now = Date()
        let state = earned(now: now)
        XCTAssertTrue(state.shouldPrompt(now: now), "usage is earned")
        XCTAssertEqual(state.canPrompt(now: now), Donations.isConfigured,
                       "showing the prompt must additionally require real links")
    }

    // MARK: - Coordinator

    /// A scratch defaults domain, so a test run never touches the real counters.
    private func scratchDefaults(_ name: String, seed: DonationState?) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        if let seed {
            defaults.set(try JSONEncoder().encode(seed), forKey: "donationState")
        }
        return defaults
    }

    /// The one this pins: reopening the popover must not produce a second ask.
    /// The prompt is recorded when shown, not when acted on, so the cooldown
    /// starts immediately.
    @MainActor
    func test_reopeningPopover_doesNotAskTwice() throws {
        let defaults = try scratchDefaults(#function, seed: earned(now: Date()))
        let coordinator = DonationCoordinator(defaults: defaults)

        coordinator.popoverDidOpen()
        XCTAssertTrue(coordinator.isShowing, "an earned user should see it once")

        coordinator.dismiss()
        coordinator.popoverDidOpen()
        XCTAssertFalse(coordinator.isShowing, "closing and reopening must not re-ask")

        // Nor on the next launch.
        let relaunched = DonationCoordinator(defaults: defaults)
        relaunched.popoverDidOpen()
        XCTAssertFalse(relaunched.isShowing)
    }

    @MainActor
    func test_optOut_survivesRelaunch() throws {
        let defaults = try scratchDefaults(#function, seed: earned(now: Date()))
        let coordinator = DonationCoordinator(defaults: defaults)
        coordinator.popoverDidOpen()
        coordinator.optOut()
        XCTAssertFalse(coordinator.isShowing)

        let relaunched = DonationCoordinator(defaults: defaults)
        relaunched.popoverDidOpen()
        XCTAssertFalse(relaunched.isShowing, "\"No thanks\" must outlive the process")
    }

    /// Nothing to show someone who installed it this morning.
    @MainActor
    func test_freshInstall_coordinatorStaysQuiet() throws {
        let defaults = try scratchDefaults(#function, seed: nil)
        let coordinator = DonationCoordinator(defaults: defaults)
        coordinator.recordToggle()
        coordinator.popoverDidOpen()
        XCTAssertFalse(coordinator.isShowing)
    }

    /// The three lifetime asks are meant to escalate (opener, reminder, last
    /// chance), not repeat. A pool chosen at random could show the same message
    /// twice, or the "last one" line before it actually was the last one.
    @MainActor
    func test_threeLifetimeAsks_eachGetADifferentEscalatingPitch() throws {
        var state = earned(now: Date())
        let defaults = try scratchDefaults(#function, seed: nil)
        var headlines: [String] = []

        for _ in 0..<Donations.maximumLifetimePrompts {
            defaults.set(try JSONEncoder().encode(state), forKey: "donationState")
            let coordinator = DonationCoordinator(defaults: defaults)
            coordinator.popoverDidOpen()
            headlines.append(try XCTUnwrap(coordinator.pitch).headline)
            // Clear the cooldown for the next iteration the same way a real
            // 121-day wait would, rather than re-deriving the stored state by hand.
            state.recordPrompt(now: Date(timeIntervalSinceNow: -Double(Donations.cooldownDays + 1) * 86_400))
        }

        XCTAssertEqual(headlines.count, 3)
        XCTAssertEqual(Set(headlines).count, 3, "all three asks must read as distinct messages")
        XCTAssertEqual(headlines.first, "Windbar is free", "the opener is always the first ask")
    }

    // MARK: - Manual open, from the footer

    /// The whole point: opting out of the app's own asks must not lock the door
    /// for someone who comes looking for it themselves later.
    @MainActor
    func test_showManually_worksEvenAfterPermanentOptOut() throws {
        var state = earned(now: Date())
        state.optedOut = true
        let defaults = try scratchDefaults(#function, seed: state)
        let coordinator = DonationCoordinator(defaults: defaults)

        coordinator.popoverDidOpen()
        XCTAssertFalse(coordinator.isShowing, "an opted-out user must not get the automatic ask")

        coordinator.showManually()
        XCTAssertTrue(coordinator.isShowing, "but they can still find it themselves")
        XCTAssertEqual(coordinator.pitch?.headline, "Support Windbar")
        XCTAssertEqual(coordinator.pitch?.allowsOptOut, false, "nothing to opt out of here")
    }

    /// Also works before anything is earned: a brand new user who wants to give
    /// on day one should not have to wait out the 14-day gate to find the link.
    @MainActor
    func test_showManually_worksOnAFreshInstall() throws {
        let defaults = try scratchDefaults(#function, seed: nil)
        let coordinator = DonationCoordinator(defaults: defaults)
        coordinator.showManually()
        XCTAssertTrue(coordinator.isShowing)
    }

    /// A manual open is presentation only. It must not consume one of the three
    /// lifetime asks or reset the cooldown, or opening it defensively would cost
    /// the user a real, earned ask later.
    @MainActor
    func test_showManually_doesNotPersistOrCountAsALifetimeAsk() throws {
        let defaults = try scratchDefaults(#function, seed: nil)
        let coordinator = DonationCoordinator(defaults: defaults)
        coordinator.showManually()
        XCTAssertTrue(coordinator.isShowing)

        let reloaded = DonationCoordinator(defaults: defaults)
        XCTAssertNil(reloaded.pitch, "a manual open must not have saved anything")
    }

    // MARK: - After donating

    /// The one that matters most here: a donor must never be asked again. Before
    /// this, tapping an amount only closed the card, so four months later they
    /// were asked whether the app was still earning its spot.
    @MainActor
    func test_donating_endsTheAutomaticAsksForGood() throws {
        let defaults = try scratchDefaults(#function, seed: earned(now: Date()))
        let coordinator = DonationCoordinator(defaults: defaults)

        coordinator.popoverDidOpen()
        XCTAssertTrue(coordinator.isShowing)
        coordinator.recordDonation()
        XCTAssertFalse(coordinator.isShowing)

        // Not now, and not on any later launch, cooldown elapsed or not.
        let relaunched = DonationCoordinator(defaults: defaults)
        relaunched.popoverDidOpen()
        XCTAssertFalse(relaunched.isShowing, "a donor must not be asked again")
        XCTAssertTrue(relaunched.hasDonated)
    }

    func test_donating_outranksEveryOtherGate() {
        var state = earned(now: Date())
        XCTAssertTrue(state.shouldPrompt(), "this user is otherwise fully earned")

        state.recordDonation()

        XCTAssertFalse(state.shouldPrompt())
        XCTAssertTrue(state.hasDonated)
    }

    /// The door stays open, but it greets them rather than pitching them.
    @MainActor
    func test_donorOpeningItManually_isThankedNotAskedAgain() throws {
        let defaults = try scratchDefaults(#function, seed: earned(now: Date()))
        let coordinator = DonationCoordinator(defaults: defaults)
        coordinator.recordDonation()

        coordinator.showManually()

        XCTAssertTrue(coordinator.isShowing)
        XCTAssertEqual(coordinator.pitch?.headline, DonationPitch.alreadyGave.headline)
        XCTAssertEqual(coordinator.pitch?.allowsOptOut, false, "nothing left to opt out of")
    }

    @MainActor
    func test_someoneWhoNeverGave_stillGetsTheOrdinaryManualCard() throws {
        let defaults = try scratchDefaults(#function, seed: nil)
        let coordinator = DonationCoordinator(defaults: defaults)

        coordinator.showManually()

        XCTAssertEqual(coordinator.pitch?.headline, DonationPitch.manual.headline)
        XCTAssertFalse(coordinator.hasDonated)
    }

    /// Giving again has to stay possible, so a second donation is counted
    /// rather than ignored.
    @MainActor
    func test_donatingAgainIsCounted() throws {
        let defaults = try scratchDefaults(#function, seed: nil)
        let coordinator = DonationCoordinator(defaults: defaults)

        coordinator.recordDonation()
        coordinator.recordDonation()

        let relaunched = DonationCoordinator(defaults: defaults)
        XCTAssertTrue(relaunched.hasDonated)
    }

    func test_stateRoundTripsThroughCodable() throws {
        let now = Date()
        let state = earned(now: now)
        let decoded = try JSONDecoder().decode(
            DonationState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state, "counters must survive a relaunch")
    }
}
#endif
