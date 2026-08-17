import XCTest
@testable import Windbar

final class DreoSocketServiceTests: XCTestCase {
    func test_encodeCommand_producesExpectedEnvelope() throws {
        let text = try DreoSocketService.encodeCommand(serialNumber: "SN123", key: "poweron", value: .bool(true))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])

        XCTAssertEqual(json["devicesn"] as? String, "SN123")
        XCTAssertEqual(json["method"] as? String, "control")
        let params = try XCTUnwrap(json["params"] as? [String: Any])
        XCTAssertEqual(params["poweron"] as? Bool, true)
        XCTAssertNotNil(json["timestamp"] as? String)
    }

    /// A refused command must not be retried: the fan already judged the
    /// value, so sending it again earns the same answer.
    func test_rejection_isNotRetryable() {
        XCTAssertFalse(DreoSocketError.rejected(code: 500003, message: "instruction validate failed").isRetryable)
        XCTAssertTrue(DreoSocketError.ackTimeout.isRetryable)
        XCTAssertTrue(DreoSocketError.notConnected.isRetryable)
    }

    func test_webSocketURL_usesRegionHostAndIncludesToken() throws {
        let session = DreoSession(accessToken: "tok-abc", regionHost: "eu")
        let url = try XCTUnwrap(DreoSocketService.webSocketURL(for: session))

        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.host, "wsb-eu.dreo-tech.com")
        XCTAssertEqual(url.path, "/websocket")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let token = components.queryItems?.first(where: { $0.name == "accessToken" })?.value
        XCTAssertEqual(token, "tok-abc")
    }
}
