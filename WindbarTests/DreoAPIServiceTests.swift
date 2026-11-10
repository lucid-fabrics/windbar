import CryptoKit
import XCTest
@testable import Windbar

final class DreoAPIServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocolStub.handler = nil
        super.tearDown()
    }

    func test_login_matchingRegion_storesTokenFromSingleRequest() async throws {
        var requestCount = 0
        MockURLProtocolStub.handler = { request in
            requestCount += 1
            XCTAssertEqual(request.url?.host, "app-api-us.dreo-tech.com")
            XCTAssertEqual(request.url?.path, "/api/oauth/login")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ua"), "dreo/2.8.2")

            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.bodyData(from: request)) as? [String: Any])
            XCTAssertEqual(body["email"] as? String, "user@example.com")
            XCTAssertEqual(body["grant_type"] as? String, "email-password")
            let expectedHash = Insecure.MD5.hash(data: Data("secret".utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(body["password"] as? String, expectedHash)

            let responseBody = #"{"code":0,"msg":"OK","data":{"access_token":"tok-123","region":"NA"}}"#
            return (Self.httpResponse(for: request), Data(responseBody.utf8))
        }

        let service = DreoAPIService(urlSession: MockURLProtocolStub.makeSession())
        try await service.login(DreoCredentials(email: "user@example.com", password: "secret"))

        let session = await service.currentSession()
        XCTAssertEqual(session?.accessToken, "tok-123")
        XCTAssertEqual(session?.regionHost, "us")
        XCTAssertEqual(requestCount, 1)
    }

    func test_login_capturesNumericUserIdForBLEPairing() async throws {
        MockURLProtocolStub.handler = { request in
            // `userid` arrives as a bare JSON number past Int32 range; BLE
            // pairing needs it exactly to bind a new fan to this account.
            let responseBody = """
            {"code":0,"msg":"OK","data":{"access_token":"tok","region":"NA","userid":1234567890123456789}}
            """
            return (Self.httpResponse(for: request), Data(responseBody.utf8))
        }

        let service = DreoAPIService(urlSession: MockURLProtocolStub.makeSession())
        try await service.login(DreoCredentials(email: "user@example.com", password: "secret"))

        let session = await service.currentSession()
        XCTAssertEqual(session?.userId, 1_234_567_890_123_456_789)
        XCTAssertEqual(session?.deviceAPIHost, "https://device-api-us.dreo-cloud.com")
    }

    func test_login_missingUserId_leavesSessionUsable() async throws {
        MockURLProtocolStub.handler = { request in
            let responseBody = #"{"code":0,"msg":"OK","data":{"access_token":"tok","region":"NA"}}"#
            return (Self.httpResponse(for: request), Data(responseBody.utf8))
        }

        let service = DreoAPIService(urlSession: MockURLProtocolStub.makeSession())
        try await service.login(DreoCredentials(email: "user@example.com", password: "secret"))

        let session = await service.currentSession()
        XCTAssertNil(session?.userId)
        XCTAssertEqual(session?.accessToken, "tok")
    }

    func test_login_regionMismatch_retriesOnceAgainstCorrectHost() async throws {
        var hosts: [String] = []
        MockURLProtocolStub.handler = { request in
            hosts.append(request.url?.host ?? "")
            let responseBody = #"{"code":0,"msg":"OK","data":{"access_token":"tok-eu","region":"EU"}}"#
            return (Self.httpResponse(for: request), Data(responseBody.utf8))
        }

        let service = DreoAPIService(urlSession: MockURLProtocolStub.makeSession())
        try await service.login(DreoCredentials(email: "user@example.com", password: "secret"))

        XCTAssertEqual(hosts, ["app-api-us.dreo-tech.com", "app-api-eu.dreo-tech.com"])
        let session = await service.currentSession()
        XCTAssertEqual(session?.regionHost, "eu")
    }

    func test_listDevices_parsesSerialNumberAndControlsConf() async throws {
        MockURLProtocolStub.handler = { request in
            if request.url?.path == "/api/oauth/login" {
                let body = #"{"code":0,"msg":"OK","data":{"access_token":"tok","region":"NA"}}"#
                return (Self.httpResponse(for: request), Data(body.utf8))
            }
            XCTAssertEqual(request.url?.path, "/api/v2/user-device/device/list")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer tok")
            let body = #"""
            {"code":0,"msg":"OK","data":{"list":[
                {"sn":"SN123","deviceName":"Tower Fan","model":"DR-HTF004S",
                 "controlsConf":{"control":[{"id":"110","type":"Speed","title":"device_control_speed",
                 "items":[{"text":"1","cmd":"windlevel","value":1},{"text":"12","cmd":"windlevel","value":12}]}],
                 "preference":[]}}
            ]}}
            """#
            return (Self.httpResponse(for: request), Data(body.utf8))
        }

        let service = DreoAPIService(urlSession: MockURLProtocolStub.makeSession())
        try await service.login(DreoCredentials(email: "user@example.com", password: "secret"))
        let devices = try await service.listDevices()

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].serialNumber, "SN123")
        XCTAssertEqual(devices[0].deviceName, "Tower Fan")
        XCTAssertEqual(devices[0].controlsConf?.control.first?.items?.count, 2)
    }

    func test_listDevices_keepsDevicesWhoseControlsConfHasNoSections() async throws {
        MockURLProtocolStub.handler = { request in
            if request.url?.path == "/api/oauth/login" {
                let body = #"{"code":0,"msg":"OK","data":{"access_token":"tok","region":"NA"}}"#
                return (Self.httpResponse(for: request), Data(body.utf8))
            }
            // SN2 sends a controlsConf carrying only "template", which is
            // what a newer model returns. It must neither discard the other
            // device nor be left uncontrollable.
            let body = #"""
            {"code":0,"msg":"OK","data":{"list":[
                {"sn":"SN1","deviceName":"Tower Fan","model":"DR-HTF004S",
                 "controlsConf":{"control":[{"id":"110","type":"Speed","title":"speed",
                 "items":[{"text":"1","cmd":"windlevel","value":1}]}],"preference":[]}},
                {"sn":"SN2","deviceName":"Air Circulator","model":"DR-HPF008S",
                 "controlsConf":{"template":"someTemplate"}},
                {"sn":"SN3","deviceName":"Mystery","model":"DR-NOT-A-REAL-MODEL",
                 "controlsConf":{"template":"unknown"}}
            ]}}
            """#
            return (Self.httpResponse(for: request), Data(body.utf8))
        }

        let service = DreoAPIService(urlSession: MockURLProtocolStub.makeSession())
        try await service.login(DreoCredentials(email: "user@example.com", password: "secret"))
        let devices = try await service.listDevices()

        XCTAssertEqual(devices.map(\.serialNumber), ["SN1", "SN2", "SN3"])
        // The server's own schema wins where it sent one.
        XCTAssertEqual(devices[0].controlsConf?.control.count, 1)
        // A schema-less known model is filled in from the bundled catalog.
        XCTAssertEqual(devices[1].controlsConf?.isEmpty, false)
        XCTAssertNotNil(devices[1].controlsConf?.control.first { $0.type == "Speed" })
        // An unknown model stays empty rather than borrowing someone else's.
        XCTAssertEqual(devices[2].controlsConf?.isEmpty, true)
    }

    func test_listDevices_dropsOnlyTheUnparseableDevice() async throws {
        MockURLProtocolStub.handler = { request in
            if request.url?.path == "/api/oauth/login" {
                let body = #"{"code":0,"msg":"OK","data":{"access_token":"tok","region":"NA"}}"#
                return (Self.httpResponse(for: request), Data(body.utf8))
            }
            // Second entry is missing the required "sn"; the others survive.
            let body = #"""
            {"code":0,"msg":"OK","data":{"list":[
                {"sn":"SN1","deviceName":"A","model":"M1"},
                {"deviceName":"Broken","model":"M2"},
                {"sn":"SN3","deviceName":"C","model":"M3"}
            ]}}
            """#
            return (Self.httpResponse(for: request), Data(body.utf8))
        }

        let service = DreoAPIService(urlSession: MockURLProtocolStub.makeSession())
        try await service.login(DreoCredentials(email: "user@example.com", password: "secret"))
        let devices = try await service.listDevices()

        XCTAssertEqual(devices.map(\.serialNumber), ["SN1", "SN3"])
    }

    func test_fetchState_flattensWrappedAndRawValues() async throws {
        MockURLProtocolStub.handler = { request in
            if request.url?.path == "/api/oauth/login" {
                let body = #"{"code":0,"msg":"OK","data":{"access_token":"tok","region":"NA"}}"#
                return (Self.httpResponse(for: request), Data(body.utf8))
            }
            XCTAssertEqual(request.url?.path, "/api/user-device/device/state")
            // "timeron"/"timeroff" carry a nested object as their state on
            // real devices, and "bogus" an array nothing can represent. The
            // object has to survive, and the one bad field must not take
            // down decoding of every other field.
            let body = #"""
            {"code":0,"msg":"OK","data":{"mixed":{
                "poweron":{"state":true,"timestamp":123},
                "windlevel":5,
                "hoscangle":"-45,45",
                "timeron":{"state":{"du":0,"ts":1785109942},"timestamp":null},
                "bogus":{"state":[1,2],"timestamp":null}
            }}}
            """#
            return (Self.httpResponse(for: request), Data(body.utf8))
        }

        let service = DreoAPIService(urlSession: MockURLProtocolStub.makeSession())
        try await service.login(DreoCredentials(email: "user@example.com", password: "secret"))
        let state = try await service.fetchState(for: "SN123")

        XCTAssertEqual(state["poweron"], .bool(true))
        XCTAssertEqual(state["windlevel"], .int(5))
        XCTAssertEqual(state["hoscangle"], .string("-45,45"))
        XCTAssertEqual(state["timeron"], .object(["du": .int(0), "ts": .int(1785109942)]))
        XCTAssertNil(state["bogus"])
    }

    func test_listDevices_on401_reauthenticatesAndRetries() async throws {
        var deviceListAttempts = 0
        var loginAttempts = 0
        MockURLProtocolStub.handler = { request in
            if request.url?.path == "/api/oauth/login" {
                loginAttempts += 1
                let body = #"{"code":0,"msg":"OK","data":{"access_token":"tok-\#(loginAttempts)","region":"NA"}}"#
                return (Self.httpResponse(for: request), Data(body.utf8))
            }
            deviceListAttempts += 1
            if deviceListAttempts == 1 {
                return (Self.httpResponse(for: request, statusCode: 401), Data())
            }
            let body = #"{"code":0,"msg":"OK","data":{"list":[]}}"#
            return (Self.httpResponse(for: request), Data(body.utf8))
        }

        let service = DreoAPIService(urlSession: MockURLProtocolStub.makeSession())
        try await service.login(DreoCredentials(email: "user@example.com", password: "secret"))
        let devices = try await service.listDevices()

        XCTAssertEqual(devices, [])
        XCTAssertEqual(deviceListAttempts, 2)
        XCTAssertEqual(loginAttempts, 2)
        let session = await service.currentSession()
        XCTAssertEqual(session?.accessToken, "tok-2")
    }

    private static func httpResponse(for request: URLRequest, statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    /// URLSession delivers a POST body to URLProtocol via `httpBodyStream`,
    /// not `httpBody`, so tests need to drain the stream themselves.
    private static func bodyData(from request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
