import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodexHubManagementTests {
    @Test(arguments: [
        (
            #"""
            {
              "schemaVersion": 1,
              "proxy": {
                "running": true
              },
              "runtimeRole": "client",
              "connection": {
                "state": "connected",
                "managementUrl": "https://hub.example"
              },
              "dashboard": {
                "url": "http://localhost:10100/"
              }
            }
            """#,
            "https://hub.example/#providers?provider=anthropic&tab=accounts"),
        (
            #"""
            {
              "schemaVersion": 1,
              "proxy": {
                "running": true
              },
              "runtimeRole": "hub",
              "hub": {
                "managementPublicOrigin": "https://new-hub.example/"
              }
            }
            """#,
            "https://new-hub.example/#providers?provider=anthropic&tab=accounts"),
        (
            #"""
            {
              "schemaVersion": 1,
              "proxy": {
                "running": true
              },
              "runtimeRole": "standalone",
              "dashboard": {
                "url": "http://localhost:10100/"
              }
            }
            """#,
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
        #"""
        {
          "schemaVersion": 2,
          "proxy": {
            "running": true
          },
          "runtimeRole": "hub",
          "hub": {
            "managementPublicOrigin": "https://hub.example/"
          }
        }
        """#,
        #"""
        {
          "schemaVersion": 1,
          "proxy": {
            "running": false
          },
          "runtimeRole": "hub",
          "hub": {
            "managementPublicOrigin": "https://hub.example/"
          }
        }
        """#,
        #"""
        {
          "schemaVersion": true,
          "proxy": {
            "running": true
          },
          "runtimeRole": "hub",
          "hub": {
            "managementPublicOrigin": "https://hub.example/"
          }
        }
        """#,
        #"""
        {
          "schemaVersion": 1,
          "proxy": {
            "running": 1
          },
          "runtimeRole": "hub",
          "hub": {
            "managementPublicOrigin": "https://hub.example/"
          }
        }
        """#,
        #"""
        {
          "schemaVersion": 1,
          "proxy": {
            "running": true
          },
          "runtimeRole": "client",
          "connection": {
            "state": "disconnected",
            "managementUrl": "https://old.example"
          }
        }
        """#,
        #"""
        {
          "schemaVersion": 1,
          "proxy": {
            "running": true
          },
          "runtimeRole": "client",
          "connection": {
            "state": "connected",
            "serverUrl": "https://data.example"
          },
          "dashboard": {
            "url": "http://localhost:10100/"
          }
        }
        """#,
        #"""
        {
          "schemaVersion": 1,
          "proxy": {
            "running": true
          },
          "runtimeRole": "standalone",
          "dashboard": {
            "url": "https://remote.example/"
          }
        }
        """#,
        #"""
        {
          "schemaVersion": 1,
          "proxy": {
            "running": true
          },
          "runtimeRole": "unknown",
          "hub": {
            "managementPublicOrigin": "https://hub.example/"
          }
        }
        """#,
    ])
    func `missing management authority never falls back to the data plane`(status: String) {
        #expect(OpenCodexHubManagement.accountsURL(status: Data(status.utf8), provider: .xai) == nil)
    }

    @Test(arguments: ["http://127.0.0.1:65130", "https://hub.example/"])
    func `remote links never open their transport URL as a browser UI`(reported: String) throws {
        let data = try self.linkStatus(reported: reported)
        #expect(OpenCodexHubManagement.accountsURL(status: data, provider: .anthropic) == nil)
        let url = OpenCodexHubManagement.accountsURL(
            status: data, provider: .anthropic, managementOrigin: "https://management.example/")
        #expect(url?.absoluteString == "https://management.example/#providers?provider=anthropic&tab=accounts")
    }

    @Test(arguments: [
        "http://127.0.0.1:65130", "https://localhost:65130", "https://127.0.0.1:65130", "https://[::1]/",
        "http://hub.example/", "https://hub.example/v1", "https://user:secret@hub.example/",
        "https://hub.example/?token=synthetic", "https://hub.example/#pair=synthetic",
        "https://hub.example:0", "https://hub.example:65536", "https://hub.example/\npath",
    ])
    func `configured browser origins reject data paths credentials and loopback`(origin: String) throws {
        #expect(!OpenCodexHubManagement.isRemoteManagementOrigin(origin))
        #expect(OpenCodexHubManagement.canonicalManagementOrigin(origin) == nil)
        #expect(try OpenCodexHubManagement.accountsURL(
            status: self.linkStatus(), provider: .openai, managementOrigin: origin) == nil)
    }

    @Test(arguments: [
        "not json", "{}", "{\"schemaVersion\":2}",
        "{\"schemaVersion\":1,\"runtimeRole\":\"hub\",\"proxy\":{\"running\":false}}",
        "{\"schemaVersion\":1,\"runtimeRole\":\"unknown\",\"proxy\":{\"running\":true}}",
        """
        {"schemaVersion":1,"runtimeRole":"client","proxy":{"running":true},
        "connection":{"state":"disconnected","transport":"link"}}
        """,
    ])
    func `explicit origins do not depend on local status`(status: String) {
        let data = Data(status.utf8)
        #expect(OpenCodexHubManagement.accountsURL(
            status: data, provider: .openai, managementOrigin: "https://management.example")?
            .absoluteString == "https://management.example/#codex-set")
        for origin: String? in [nil, "", " \n\t "] {
            #expect(OpenCodexHubManagement.accountsURL(
                status: data, provider: .openai, managementOrigin: origin) == nil)
        }
    }

    @Test
    func `explicit origins do not parse oversized status`() {
        let status = Data(repeating: 0x20, count: OpenCodexHubReader.maxOutputBytes + 1)
        #expect(OpenCodexHubManagement.accountsURL(
            status: status, provider: .openai, managementOrigin: "https://management.example")?
            .absoluteString == "https://management.example/#codex-set")
        #expect(OpenCodexHubManagement.accountsURL(status: status, provider: .openai) == nil)
    }

    @Test(arguments: ["https://management.example", " \nhttps://management.example/\t "])
    func `explicit origins select every provider before transport or executable lookup`(origin: String) async throws {
        let transport = HubManagementTransport()
        await transport.fail()
        for provider in [OpenCodexHubProvider.openai, .anthropic, .xai] {
            let fragment = provider == .openai ? "codex-set" : "providers?provider=\(provider.rawValue)&tab=accounts"
            let url = try await OpenCodexHubManagement.accountsURL(
                executablePath: nil, provider: provider, managementOrigin: origin, transport: transport)
            #expect(url.absoluteString == "https://management.example/#\(fragment)")
        }
        #expect(await transport.arguments.isEmpty)
        for variant in [origin, "HTTPS://Management.Example:443/"] {
            #expect(OpenCodexHubManagement.canonicalManagementOrigin(variant) == "https://management.example")
        }
        #expect(OpenCodexHubManagement.canonicalManagementOrigin("https://management.example:8443/")
            == "https://management.example:8443")
    }

    @Test(arguments: [
        "http://management.example", "https://management.example/path", "https://localhost/",
        "https://127.0.0.2/", "https://localhost./", "https://127.1/", "https://[::ffff:127.0.0.1]/",
        "https://[::1%25lo0]/", "https://[::ffff:127.0.0.1%25lo0]/", "https://[fe80::1%25en0]/",
        "https://user:secret@management.example", "https://management.example/?", "https://management.example/#",
    ])
    func `invalid explicit origins fail closed without consulting status or transport`(origin: String) async throws {
        let transport = HubManagementTransport()
        #expect(!OpenCodexHubManagement.isRemoteManagementOrigin(origin))
        for role in ["hub", "standalone", "client"] {
            let status = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "runtimeRole": role, "proxy": ["running": true],
                "hub": ["managementPublicOrigin": "https://hub.example"],
                "dashboard": ["url": "http://localhost:10100/"],
                "connection": ["state": "connected", "managementUrl": "https://hub.example"],
            ])
            #expect(OpenCodexHubManagement.accountsURL(
                status: status, provider: .openai, managementOrigin: origin) == nil)
        }
        await #expect(throws: OpenCodexHubManagementError.managementAddressRequired) {
            _ = try await OpenCodexHubManagement.accountsURL(
                executablePath: "/fake/ocx", provider: .openai, managementOrigin: origin, transport: transport)
        }
        #expect(await transport.arguments.isEmpty)
    }

    @Test(arguments: ["\"\"", "' '", "\"https://management.example\"", "not a URL"])
    func `origin config preserves invalid nonempty values for fail closed selection`(origin: String) {
        var config = ProviderConfig(id: .claude)
        config.openCodexHubManagementOrigin = " \n\(origin)\t "
        #expect(config.sanitizedOpenCodexHubManagementOrigin == origin)
    }

    private func linkStatus(reported: String = "http://127.0.0.1:65130") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "proxy": ["running": true], "runtimeRole": "client", "connection": [
                "state": "connected", "transport": "link", "managementUrl": reported,
                "serverUrl": "https://data.example",
            ],
        ])
    }

    @Test(arguments: [nil, "", " \n\t "] as [String?])
    func `opening management reads only current status and sanitizes transport failures`(origin: String?) async throws {
        let transport = HubManagementTransport()
        let url = try await OpenCodexHubManagement.accountsURL(
            executablePath: "/fake/ocx", provider: .xai, managementOrigin: origin, transport: transport)
        #expect(url.absoluteString == "https://hub.example/#providers?provider=xai&tab=accounts")
        #expect(await transport.arguments == [["status", "--json"]])
        #expect(await transport.mutations == [false])
        await transport.fail()
        await #expect(throws: OpenCodexAccessError.communicationFailed) {
            _ = try await OpenCodexHubManagement.accountsURL(
                executablePath: "/fake/ocx", provider: .xai, managementOrigin: origin, transport: transport)
        }
        // Hub and client roles need the central address; the role is read even from a failing exit.
        func document(_ role: String, running: Bool, _ extra: [String: Any] = [:]) throws -> String {
            let object = extra.merging(["schemaVersion": 1, "runtimeRole": role, "proxy": ["running": running]]) {
                $1
            }
            return try String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        }
        let addressRequired: [(status: String?, exitCode: Int32)] = try [
            (nil, 0),
            (document("hub", running: false, ["token": "synthetic-private-output"]), 0),
            (document("hub", running: false), 1),
            (#"{"runtimeRole":"hub","hub":{"managementPublicOrigin":"https://hub.example"}}"#, 0),
            (document("hub", running: true, ["hub": [:]]), 0),
            (document("client", running: false), 0),
            (document("client", running: true, ["connection": ["state": "disconnected"]]), 2),
            (String(decoding: self.linkStatus(), as: UTF8.self), 0),
        ]
        for (status, exitCode) in addressRequired {
            await transport.respond(status, exitCode: exitCode)
            await #expect(throws: OpenCodexHubManagementError.managementAddressRequired) {
                _ = try await OpenCodexHubManagement.accountsURL(
                    executablePath: "/fake/ocx", provider: .xai, managementOrigin: origin, transport: transport)
            }
        }
        let unreachable: [(status: String, exitCode: Int32)] = try [
            (document("standalone", running: false), 0),
            (document("standalone", running: true, ["dashboard": ["url": "https://remote.example/"]]), 1),
            (document("unknown", running: true), 0),
            (document("future", running: true), 0),
            ("synthetic-private-output", 1), ("[]", 0), ("", 0),
        ]
        for (status, exitCode) in unreachable {
            await transport.respond(status, exitCode: exitCode)
            await #expect(throws: OpenCodexHubReaderError.noHubSource("no connected, secure management address")) {
                _ = try await OpenCodexHubManagement.accountsURL(
                    executablePath: "/fake/ocx", provider: .xai, managementOrigin: origin, transport: transport)
            }
        }
        #expect(await transport.acceptedNonZeroExit.allSatisfy(\.self))
    }
}

private actor HubManagementTransport: OpenCodexAccessTransport {
    var arguments: [[String]] = []
    var mutations: [Bool] = []
    var acceptedNonZeroExit: [Bool] = []
    private var failing = false
    /// nil models a configured executable that does not exist.
    private var response: (status: String?, exitCode: Int32)?

    func fail() { self.failing = true }

    func respond(_ status: String?, exitCode: Int32) {
        self.failing = false
        self.response = (status, exitCode)
    }

    func run(_ request: OpenCodexAccessRequest) async throws -> Data {
        self.arguments.append(request.arguments)
        self.mutations.append(request.mutation)
        self.acceptedNonZeroExit.append(request.acceptsNonZeroExit)
        if self.failing { throw NSError(domain: "synthetic-private-output", code: 1) }
        if let response {
            guard let status = response.status else { throw OpenCodexAccessError.executableMissing }
            // Mirrors the process transport: a non-zero exit throws unless the request accepts it.
            guard response.exitCode == 0 || request.acceptsNonZeroExit else {
                throw OpenCodexAccessError.communicationFailed
            }
            return Data(status.utf8)
        }
        return Data(
            #"""
            {
              "schemaVersion": 1,
              "proxy": {
                "running": true
              },
              "runtimeRole": "client",
              "connection": {
                "state": "connected",
                "managementUrl": "https://hub.example/"
              },
              "token": "synthetic-private-output"
            }
            """#
                .utf8)
    }
}
