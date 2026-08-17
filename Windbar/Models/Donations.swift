#if WINDBAR_DONATIONS
import Foundation
import Observation

/// Donation prompt for the direct-download build only.
///
/// This whole file compiles to nothing in the App Store build. `WINDBAR_DONATIONS`
/// is set only by `fastlane mac release_dmg`, never by `release`. That is not
/// tidiness: App Review guideline 3.1.1 forbids pointing users at a payment
/// mechanism outside the App Store, so the shipped App Store binary must not
/// contain this code at all, not merely hide it behind a flag at runtime.
///
/// THE TIMING RULES, AND WHY
///
/// Asking too early is what makes these things feel like a shakedown. The ask is
/// only earned once the app has demonstrably saved someone time, so the gate is
/// deliberately conservative on every axis:
///
/// - not before 14 days of having the app, so a trial-and-delete user never sees it
/// - not before 50 real toggles, so a curious poke does not count
/// - not before 7 separate days of use, so 50 toggles in one afternoon does not count
/// - never twice within 120 days
/// - three times in the app's whole life, then silent forever
/// - one click on "No thanks" and it never returns
///
/// Together those mean the median user sees this at most once or twice, ever, and
/// only after the app has been genuinely useful to them.
enum Donations {
    /// Live Stripe Payment Links. Checkout shows "Lucid Fabrics", which matches the
    /// GitHub org this is published under, so the name is one a donor recognises.
    /// The links are public by design; they are the whole point of shipping them.
    static let links: [(label: String, url: String)] = [
        ("$5", "https://buy.stripe.com/dRmfZg2K7aTOcD0dMMgYU00"),
        ("$10", "https://buy.stripe.com/7sY7sK1G36Dy46u6kkgYU01"),
        ("$20", "https://buy.stripe.com/cNi00i3Ob7HCbyWdMMgYU02")
    ]

    static var isConfigured: Bool { links.allSatisfy { !$0.url.isEmpty } }

    static let minimumDaysInstalled = 14
    static let minimumToggles = 50
    static let minimumActiveDays = 7
    static let cooldownDays = 120
    static let maximumLifetimePrompts = 3
}

/// What the card says. Three fixed messages, one per lifetime ask, rather than a
/// larger random pool.
///
/// A bigger rotating pool reads as copy that is being tested on people; a specific
/// message tied to real numbers from `DonationState` reads as sincere. Because the
/// message is keyed to `promptCount` rather than chosen at random, the same user
/// sees a different, escalating message each of their three asks: an opener, a
/// reminder, and an honest "this is the last one".
struct DonationPitch {
    let headline: String
    let body: String
    /// Automatic asks offer to opt out of future asks. The manually opened card
    /// has nothing to opt out of, since it never triggers itself, so it hides
    /// that row entirely rather than let "No thanks" mean something different
    /// depending on how the card got there.
    var allowsOptOut = true

    /// `promptCount` at the moment this ask fires: 0 for the first ever prompt,
    /// 1 for the second, 2 for the third and last. `state` still has the PREVIOUS
    /// count when this runs, since it is read before `recordPrompt` increments it.
    static func forAsk(_ state: DonationState) -> DonationPitch {
        let toggles = state.toggleCount
        let days = state.activeDays.count
        switch state.promptCount {
        case 0:
            return DonationPitch(
                headline: "Windbar is free",
                body: "You've reached for it \(toggles) times over \(days) days. If it saved "
                    + "you a few trips across the room, a coffee's worth helps keep it going.")
        case 1:
            return DonationPitch(
                headline: "Still earning its spot?",
                body: "\(toggles) toggles and counting, no ads, no account, no tracking. "
                    + "Chip in if it's still worth the space in your menu bar.")
        default:
            return DonationPitch(
                headline: "Last time asking, promise",
                body: "\(days) days of use and this is genuinely the last time you'll see this. "
                    + "If Windbar has been useful, now's a good moment.")
        }
    }

    /// Shown only when the user opens "Support Windbar" from the footer
    /// themselves. Available even after a permanent opt-out or the lifetime cap:
    /// declining the app's own ask should not lock the door for someone who
    /// changes their mind and comes looking for it later.
    static let manual = DonationPitch(
        headline: "Support Windbar",
        body: "No pressure, just here if you ever want to chip in.",
        allowsOptOut: false)

    /// For someone who has already given. They are never asked again, so this
    /// only ever appears because they went looking for it, which makes a
    /// second pitch the wrong thing to show them: thank them, say plainly that
    /// the asking is over, and leave the buttons working for anyone who wants
    /// to give again.
    static let alreadyGave = DonationPitch(
        headline: "You already chipped in",
        body: "Thanks, that was generous. Windbar won't ask you again. "
            + "The buttons still work if you ever feel like topping it up.",
        allowsOptOut: false)
}

/// Counters behind the prompt. Deliberately dumb and local: no identifiers, no
/// network, nothing that leaves the Mac. See docs/PRIVACY.md.
struct DonationState: Codable, Equatable, Sendable {
    var firstLaunch: Date?
    var toggleCount: Int = 0
    /// Days the app was actually used, as yyyy-MM-dd strings. A set, so ten
    /// toggles in one evening count once.
    var activeDays: Set<String> = []
    var lastPrompt: Date?
    var promptCount: Int = 0
    var optedOut: Bool = false
    /// How many times the user opened checkout from the card.
    ///
    /// Not "how many times they paid": the amount button hands off to a Stripe
    /// link in a browser and nothing comes back, so the app cannot know. Intent
    /// is treated as enough. Erring generous means someone who abandons
    /// checkout stops being asked, which is a far better failure than asking a
    /// donor whether the app is still earning its spot.
    var donationCount: Int = 0

    var hasDonated: Bool { donationCount > 0 }

    static let `default` = DonationState()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    mutating func recordUse(now: Date = Date()) {
        if firstLaunch == nil { firstLaunch = now }
        toggleCount += 1
        activeDays.insert(Self.dayFormatter.string(from: now))
    }

    mutating func recordPrompt(now: Date = Date()) {
        lastPrompt = now
        promptCount += 1
    }

    mutating func recordDonation() {
        donationCount += 1
    }

    /// Whether the user has *earned* the ask. Deliberately says nothing about
    /// whether links exist to show them: that is a deployment concern, checked
    /// separately by `canPrompt`, so this stays pure and testable.
    func shouldPrompt(now: Date = Date()) -> Bool {
        guard !optedOut else { return false }
        // Giving ends the asking permanently. The whole point of the gate is
        // that the ask has to be earned, and there is nothing left to earn
        // from someone who already paid.
        guard !hasDonated else { return false }
        guard promptCount < Donations.maximumLifetimePrompts else { return false }
        guard let first = firstLaunch else { return false }

        let days = Calendar.current.dateComponents([.day], from: first, to: now).day ?? 0
        guard days >= Donations.minimumDaysInstalled else { return false }
        guard toggleCount >= Donations.minimumToggles else { return false }
        guard activeDays.count >= Donations.minimumActiveDays else { return false }

        if let last = lastPrompt {
            let since = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0
            guard since >= Donations.cooldownDays else { return false }
        }
        return true
    }

    /// What the UI actually asks. Earned, and there is somewhere to send them.
    func canPrompt(now: Date = Date()) -> Bool {
        Donations.isConfigured && shouldPrompt(now: now)
    }
}

/// Owns the counters and decides, once per popover, whether to show the ask.
///
/// Storage is UserDefaults rather than `AppSettings` so that nothing about
/// donations exists in the types the App Store build compiles.
@MainActor
@Observable
final class DonationCoordinator {
    private(set) var isShowing = false
    private(set) var pitch: DonationPitch?
    /// Mirrored out of `state` so the footer can acknowledge a supporter
    /// without the whole counter blob having to be observable.
    private(set) var hasDonated = false

    @ObservationIgnored private var state: DonationState
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "donationState"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(DonationState.self, from: $0) } ?? DonationState()
        // Clock starts at install, not at first toggle. Someone who leaves the app
        // running untouched for three weeks has still had it for three weeks.
        if state.firstLaunch == nil {
            state.firstLaunch = Date()
            save()
        }
        hasDonated = state.hasDonated
    }

    func recordToggle() {
        state.recordUse()
        save()
    }

    /// Call when the popover opens.
    ///
    /// Records the prompt at the moment it is shown rather than when it is acted
    /// on, so closing and reopening the popover cannot produce a second ask. With
    /// the 120 day cooldown that means at most one visible ask per four months.
    func popoverDidOpen() {
        guard !isShowing, state.canPrompt() else { return }
        // Read before recordPrompt increments promptCount, so ask 1 gets index 0.
        pitch = DonationPitch.forAsk(state)
        state.recordPrompt()
        save()
        isShowing = true
    }

    /// Dismissed for now. The cooldown decides when, or whether, it returns.
    func dismiss() { isShowing = false }

    /// The user tapped an amount and checkout opened.
    ///
    /// This is the end of the automatic asks. Closing the card is not enough
    /// on its own: without recording it, a donor came back four months later
    /// to a card asking whether the app was still earning its spot.
    func recordDonation() {
        state.recordDonation()
        hasDonated = true
        save()
        isShowing = false
    }

    /// User-initiated, from the footer. Deliberately bypasses `canPrompt()`
    /// entirely and touches nothing in the ask counters: it must work even for
    /// someone who opted out or already used up all three automatic asks, and
    /// opening it must not itself count as, or block, one of those asks.
    ///
    /// Someone who has already given gets thanked rather than pitched. They
    /// are never sent here by the app, so their being here at all means they
    /// came looking, and a second pitch would be the wrong greeting.
    func showManually() {
        pitch = state.hasDonated ? .alreadyGave : .manual
        isShowing = true
    }

    /// "No thanks", which has to mean never again.
    func optOut() {
        state.optedOut = true
        save()
        isShowing = false
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.storageKey)
    }

    #if DEBUG
    // MARK: - Preview, debug builds only
    //
    // The gate is deliberately hard to satisfy: 14 days installed, 50 toggles,
    // 7 separate days of use. That is right for users and useless for anyone
    // working on the card, who would otherwise have to fake counters by hand
    // or wait a fortnight to see their own copy. These skip the gate without
    // touching it, so a preview never consumes one of the three real asks.
    //
    // Double-gated: `#if DEBUG` keeps it out of both shipping builds, and the
    // enclosing `#if WINDBAR_DONATIONS` keeps it out of the App Store one
    // twice over.

    /// Shows the ask the user would earn next, without spending it.
    func debugShowAsk() {
        pitch = DonationPitch.forAsk(state)
        isShowing = true
    }

    /// Shows a specific one of the three, so all the copy can be checked.
    func debugShowAsk(index: Int) {
        var preview = state
        preview.promptCount = index
        pitch = DonationPitch.forAsk(preview)
        isShowing = true
    }

    /// Back to a fresh install, so the whole flow can be walked again.
    func debugReset() {
        state = DonationState()
        state.firstLaunch = Date()
        hasDonated = false
        isShowing = false
        pitch = nil
        save()
    }

    /// Pretends the user has given, for checking the supporter card and the
    /// filled heart in the footer.
    func debugMarkDonated() {
        state.recordDonation()
        hasDonated = true
        isShowing = false
        save()
    }

    var debugSummary: String {
        "toggles \(state.toggleCount) · days \(state.activeDays.count) · "
            + "asks \(state.promptCount)/\(Donations.maximumLifetimePrompts) · "
            + (state.hasDonated ? "donated" : "not donated")
            + (state.optedOut ? " · opted out" : "")
    }
    #endif
}
#endif
