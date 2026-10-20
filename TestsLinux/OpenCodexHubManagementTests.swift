import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodexHubManagementTests {
    @Test(arguments: [
        (
            #"{"schemaVersion":1,"proxy":{"running":true},"runtimeRole":"client","connection":{"state":"connected","managementUrl":"https://hub.example"},"dashboard":{"url":"http://localhost:10100/"}}"#,
            "https://hub.example/#providers?provider=anthropic&tab=accounts"),
        (
            #"{"schemaVersion":1,"proxy":{"running":true},"runtimeRole":"hub","hub":{"managementPublicOrigin":"https://new-hub.example/"}}"#,
            "https://new-hub.example/#providers?provider=anthropic&tab=accounts"),
        (
            #"{"schemaVersion":1,"proxy":{"running":true},"runtimeRole":"standalone","dashboard":{"url":"http://localhost:10100/"}}"#,
            "http://localhost:10100/#providers?provider=anthropic&tab=accounts"),
    ])
    func `management uses the current role address and provider page`(status: String, expected: String) {
        #expect(OpenCodexHubManagement.accountsURL(status: Data(status.utf8), provider: .anthropic)?
            .absoluteString == expected)
        let codex = OpenCodexHubManagement.accountsURL(status: Data(status.utf8), provider: .openai)
        #expect(codex?.fragment == "codex-set")
    }

    @Test(arguments: [
        "http://remote.example/", "https://user:password@hub.example/", "https://hub.example/?key=fixture",
        "https://hub.example/#pair=fixture", "file:///tmp/hub", "https://hub.example/v1", "javascript:alert(1)",
    ])
    func `management rejects insecure or credential bearing addresses`(address: String) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "proxy": ["running": true], "runtimeRole": "client", "connection": [
                "state": "connected",
                "managementUrl": address,
            ],
        ])
        #expect(OpenCodexHubManagement.accountsURL(status: data, provider: .xai) == nil)
    }

    @Test(arguments: [
        #"{"schemaVersion":2,"proxy":{"running":true},"runtimeRole":"hub","hub":{"managementPublicOrigin":"https://hub.example/"}}"#,
        #"{"schemaVersion":1,"proxy":{"running":false},"runtimeRole":"hub","hub":{"managementPublicOrigin":"https://hub.example/"}}"#,
        #"{"schemaVersion":true,"proxy":{"running":true},"runtimeRole":"hub","hub":{"managementPublicOrigin":"https://hub.example/"}}"#,
        #"{"schemaVersion":1,"proxy":{"running":1},"runtimeRole":"hub","hub":{"managementPublicOrigin":"https://hub.example/"}}"#,
        #"{"schemaVersion":1,"proxy":{"running":true},"runtimeRole":"client","connection":{"state":"disconnected","managementUrl":"https://old.example"}}"#,
        #"{"schemaVersion":1,"proxy":{"running":true},"runtimeRole":"client","connection":{"state":"connected","serverUrl":"https://data.example"},"dashboard":{"url":"http://localhost:10100/"}}"#,
        #"{"schemaVersion":1,"proxy":{"running":true},"runtimeRole":"standalone","dashboard":{"url":"https://remote.example/"}}"#,
        #"{"schemaVersion":1,"proxy":{"running":true},"runtimeRole":"unknown","hub":{"managementPublicOrigin":"https://hub.example/"}}"#,
    ])
    func `missing management authority never falls back to the data plane`(status: String) {
        #expect(OpenCodexHubManagement.accountsURL(status: Data(status.utf8), provider: .xai) == nil)
    }

    @Test
    func `opening management reads only current status and sanitizes transport failures`() async throws {
        let transport = HubManagementTransport()
        let url = try await OpenCodexHubManagement.accountsURL(
            executablePath: "/fake/ocx", provider: .xai, transport: transport)
        #expect(url.absoluteString == "https://hub.example/#providers?provider=xai&tab=accounts")
        #expect(await transport.arguments == [["status", "--json"]])
        #expect(await transport.mutations == [false])
        await transport.fail()
        await #expect(throws: OpenCodexAccessError.communicationFailed) {
            _ = try await OpenCodexHubManagement.accountsURL(
                executablePath: "/fake/ocx", provider: .xai, transport: transport)
        }
    }
}

private actor HubManagementTransport: OpenCodexAccessTransport {
    var arguments: [[String]] = []
    var mutations: [Bool] = []
    private var failing = false

    func fail() { self.failing = true }

    func run(_ request: OpenCodexAccessRequest) async throws -> Data {
        self.arguments.append(request.arguments)
        self.mutations.append(request.mutation)
        if self.failing { throw NSError(domain: "synthetic-private-output", code: 1) }
        return Data(
            #"{"schemaVersion":1,"proxy":{"running":true},"runtimeRole":"client","connection":{"state":"connected","managementUrl":"https://hub.example/"},"token":"synthetic-private-output"}"#
                .utf8)
    }
}
