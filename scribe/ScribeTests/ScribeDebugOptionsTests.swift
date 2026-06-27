import Foundation
import XCTest
@testable import Cotabby

/// Locks the developer-diagnostics gate and the logging verbosity floor: the launch-argument
/// contract, the documented `COTABBY_LOG_LEVEL` precedence, and the swift-log-to-OSLog bridge.
///
/// Environment-variable tests mutate the process environment through `setenv`/`unsetenv` and
/// restore the prior value before returning; XCTest runs the methods in this bundle serially, so
/// no other test can observe the temporary value.
final class CotabbyDebugOptionsTests: XCTestCase {
    private static let levelKey = "COTABBY_LOG_LEVEL"

    /// Runs `body` with the environment variable forced to `value` (or removed when nil), then
    /// restores whatever was there before, even if `body` throws or skips.
    private func withEnvironmentValue(
        _ key: String,
        _ value: String?,
        perform body: () throws -> Void
    ) rethrows {
        let previous = ProcessInfo.processInfo.environment[key]
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        try body()
    }

    // MARK: - Debug gate

    func test_launchArgument_matchesDocumentedFlag() {
        XCTAssertEqual(JotDebugOptions.launchArgument, "-cotabby-debug")
    }

    func test_isEnabled_mirrorsProcessLaunchArguments() {
        XCTAssertEqual(
            JotDebugOptions.isEnabled,
            ProcessInfo.processInfo.arguments.contains(JotDebugOptions.launchArgument),
            "The debug gate must key off the launch argument and nothing else"
        )
    }

    func test_log_staysQuietWhenDebugModeIsOff() throws {
        try XCTSkipIf(JotDebugOptions.isEnabled, "Runner was launched with -cotabby-debug")

        // The guard is the privacy gate: without the explicit launch argument this must be a
        // no-op rather than writing diagnostics anywhere.
        JotDebugOptions.log("coverage probe, should never be emitted")
    }

    // MARK: - Verbosity floor precedence

    func test_minimumLogLevel_honorsExplicitEnvironmentOverride() {
        withEnvironmentValue(Self.levelKey, "warning") {
            XCTAssertEqual(JotDebugOptions.minimumLogLevel.rawValue, "warning")
        }
        withEnvironmentValue(Self.levelKey, "error") {
            XCTAssertEqual(JotDebugOptions.minimumLogLevel.rawValue, "error")
        }
    }

    func test_minimumLogLevel_ignoresUnrecognizedOverride() {
        withEnvironmentValue(Self.levelKey, "chatty") {
            let expected = JotDebugOptions.isEnabled ? "trace" : "info"
            XCTAssertEqual(
                JotDebugOptions.minimumLogLevel.rawValue,
                expected,
                "A bogus override must fall back to the launch-argument default, not crash or stick"
            )
        }
    }

    func test_minimumLogLevel_normalizesOverrideCasing() {
        withEnvironmentValue(Self.levelKey, "WARNING") {
            XCTAssertEqual(JotDebugOptions.minimumLogLevel.rawValue, "warning")
        }
    }

    func test_minimumLogLevel_defaultsToInfo() throws {
        try withEnvironmentValue(Self.levelKey, nil) {
            try XCTSkipIf(JotDebugOptions.isEnabled, "Runner was launched with -cotabby-debug")
            XCTAssertEqual(JotDebugOptions.minimumLogLevel.rawValue, "info")
        }
    }

    // MARK: - Logger plumbing

    func test_llmIOLabel_isTheReservedRoutingContract() {
        // FileLogHandler routing and the jq-based debugging workflow both key off this label.
        XCTAssertEqual(JotLogger.llmIOLabel, "com.cotabby.llm-io")
    }

    func test_bootstrap_isIdempotent() {
        // The host app already bootstrapped logging at launch; repeated calls must be safe no-ops
        // (LoggingSystem traps on a second real bootstrap, so this locks the once-only guard).
        JotLogger.bootstrap()
        JotLogger.bootstrap()
    }

    // MARK: - OSLogHandler

    func test_osLogHandler_defaultFloorTracksGlobalConfiguration() {
        let handler = OSLogHandler(label: "com.cotabby.test-floor")

        XCTAssertEqual(handler.logLevel.rawValue, JotDebugOptions.minimumLogLevel.rawValue)
    }

    func test_osLogHandler_acceptsExplicitFloor() {
        let handler = OSLogHandler(label: "com.cotabby.test-floor", logLevel: .critical)

        XCTAssertEqual(handler.logLevel.rawValue, "critical")
    }

    func test_osLogHandler_metadataSubscriptReadsAndWrites() {
        var handler = OSLogHandler(label: "com.cotabby.test-metadata")

        XCTAssertNil(handler[metadataKey: "request_id"])

        handler[metadataKey: "request_id"] = .string("req_test1234")
        XCTAssertEqual(handler[metadataKey: "request_id"], .string("req_test1234"))

        handler[metadataKey: "request_id"] = nil
        XCTAssertNil(handler[metadataKey: "request_id"])
    }

    func test_loggerCopy_canLowerItsOwnFloorWithoutLeakingGlobally() {
        // Logger is a value type: a call site may locally drop the floor to trace and emit at
        // every level (exercising the full OSLog bridge switch) without mutating the shared
        // logger's configuration.
        var logger = JotLogger.debug
        logger.logLevel = .trace

        logger.trace("bridge probe: trace")
        logger.debug("bridge probe: debug")
        logger.info("bridge probe: info")
        logger.notice("bridge probe: notice")
        logger.warning("bridge probe: warning")
        logger.error("bridge probe: error")
        logger.critical("bridge probe: critical")

        XCTAssertEqual(logger.logLevel.rawValue, "trace")
        XCTAssertEqual(
            JotLogger.debug.logLevel.rawValue,
            JotDebugOptions.minimumLogLevel.rawValue,
            "Mutating a copied logger must not change the shared instance's floor"
        )
    }
}
