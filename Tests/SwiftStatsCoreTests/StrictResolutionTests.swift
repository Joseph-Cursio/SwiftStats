//
//  StrictResolutionTests.swift
//  SwiftStatsCoreTests
//
//  Strict callee resolution (PRD §7.10) for calls through a receiver: a
//  package function sharing an external API's signature doesn't take the
//  name heuristic from calls that may reach that API.
//

@testable import SwiftStatsCore
import Testing

@Suite("Strict callee resolution")
struct StrictResolutionTests {
    @Test("a call through another receiver keeps its guess when a package function shares its signature")
    func receiverQualifiedNamesake() throws {
        let run = try EffectHarness.run(source: """
        protocol Transport { func send(_ text: String) }
        final class Client {
            let transport: any Transport
            init(transport: any Transport) { self.transport = transport }
            func send(_ text: String) { transport.send(text) }
            func greet() { send("hi") }
        }
        struct Log {
            let logger: Logger
            func info(_ message: String) { logger.info("\\(message)") }
        }
        final class Worker {
            let logger: Logger
            init(logger: Logger) { self.logger = logger }
            func tick() { logger.info("tick") }
        }
        final class Engine {
            var isRunning = true
            func stop() { isRunning = false }
            func halt() { stop() }
        }
        func shutdown(_ server: Server) { server.stop() }
        """)
        let heuristic = { (tier: EffectFacts.Tier, reason: String) in
            EffectFacts.Inferred(tier: tier, depth: 1, anchor: .heuristic, via: [reason])
        }

        // A logging facade and a direct caller of the logger it wraps both
        // keep the logger-shaped receiver's tier.
        #expect(try EffectHarness.inferred("Effects::Log::func info(_: String)", in: run)
            == heuristic(.observational, "from logger-shaped receiver `logger.info`"))
        #expect(try EffectHarness.inferred("Effects::Worker::func tick()", in: run)
            == heuristic(.observational, "from logger-shaped receiver `logger.info`"))
        // A forwarding wrapper keeps the guess for the API it wraps, and an
        // unqualified call to the wrapper takes the wrapper's tier.
        let send = try EffectHarness.inferred("Effects::Client::func send(_: String)", in: run)
        #expect(send.tier == .nonIdempotent)
        #expect(send.depth == 1)
        #expect(try EffectHarness.inferred("Effects::Client::func greet()", in: run) == EffectFacts.Inferred(
            tier: .nonIdempotent,
            depth: 2,
            anchor: .heuristic,
            via: ["calls `send(_:)`"]
        ))
        // A package `stop()` with no tier silences only the unqualified call.
        #expect(try EffectHarness.facts("Effects::Engine::func halt()", in: run).function?.inferred == nil)
        #expect(try EffectHarness.inferred("Effects::func shutdown(_: Server)", in: run).tier == .nonIdempotent)
    }
}
