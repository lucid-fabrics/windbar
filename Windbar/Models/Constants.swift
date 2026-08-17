import Foundation

enum Constants {
    enum API {
        static let clientId = "7de37c362ee54dcf9c4561812309347a"
        static let clientSecret = "32dfa0764f25451d99f94e1693498791"
        static let himei = "faede31549d649f58864093158787ec9"
        static let userAgent = "dreo/2.8.2"
        static let okhttpUserAgent = "okhttp/4.9.1"
    }

    enum Socket {
        static let pingInterval: Duration = .seconds(15)
        static let pingMessage = "2"
        /// Measured against a real fan: acks come back anywhere between 0.1s
        /// and about 3s, so the old 2s guaranteed a pointless retry on every
        /// slow one. That went unnoticed while any frame naming the device
        /// counted as an ack, since an unrelated sensor report would satisfy
        /// the wait; matching acks to their own command made the real latency
        /// visible.
        static let commandAckTimeout: Duration = .seconds(4)
        static let maxCommandRetries = 2
        static let reconnectDelay: Duration = .seconds(5)
        /// How long a control waits after its last change before going to the
        /// wire. Long enough to swallow a slider drag, short enough that a
        /// single tap still feels immediate.
        static let controlSettleDelay: Duration = .milliseconds(180)
    }

    enum Keychain {
        static let service = "com.lucidfabrics.windbar.credentials"
        static let emailAccount = "email"
        static let passwordAccount = "password"
    }
}
