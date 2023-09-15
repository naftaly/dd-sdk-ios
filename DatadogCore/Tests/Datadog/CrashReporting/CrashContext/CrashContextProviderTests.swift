/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
#if canImport(CoreTelephony)
import CoreTelephony
#endif

import DatadogInternal
import TestUtilities

@testable import DatadogRUM
@testable import DatadogCrashReporting
@testable import DatadogCore

/// This suite tests if `CrashContextProvider` gets updated by different SDK components, each updating
/// separate part of the `CrashContext` information.
class CrashContextProviderTests: XCTestCase {
    var crashContextProvider: CrashContextCoreProvider! // swiftlint:disable:this implicitly_unwrapped_optional
    var core: PassthroughCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()

        crashContextProvider = CrashContextCoreProvider()
        core = PassthroughCoreMock(messageReceiver: crashContextProvider)
    }

    override func tearDown() {
        super.tearDown()

        crashContextProvider.flush()
        crashContextProvider = nil
        core = nil
    }

    // MARK: - `DatadogContext` Integration

    func testWhenTrackingConsentValueChangesInConsentProvider_thenCrashContextProviderNotifiesNewContext() {
        let expectation = self.expectation(description: "Notify new crash context")

        // Given

        let context: DatadogContext = .mockRandom()

        // When
        crashContextProvider.onCrashContextChange = {
            XCTAssertEqual($0.serverTimeOffset, context.serverTimeOffset)
            XCTAssertEqual($0.service, context.service)
            XCTAssertEqual($0.env, context.env)
            XCTAssertEqual($0.version, context.version)
            XCTAssertEqual($0.device.osVersion, context.device.osVersion)
            XCTAssertEqual($0.sdkVersion, context.sdkVersion)
            XCTAssertEqual($0.source, context.source)
            XCTAssertEqual($0.trackingConsent, context.trackingConsent)
            DDAssertReflectionEqual($0.userInfo, context.userInfo)
            XCTAssertEqual($0.networkConnectionInfo, context.networkConnectionInfo)
            XCTAssertEqual($0.carrierInfo, context.carrierInfo)
            XCTAssertEqual($0.lastIsAppInForeground, context.applicationStateHistory.currentSnapshot.state.isRunningInForeground)
            expectation.fulfill()
        }

        core.send(message: .context(context))

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    // MARK: - `RUMViewEvent` Integration

    func testWhenNewRUMView_thenItNotifiesNewCrashContext() throws {
        let expectation = self.expectation(description: "Notify new crash context")

        let viewEvent = AnyCodable(mockRandomAttributes())

        // When
        crashContextProvider.onCrashContextChange = {
            DDAssertJSONEqual($0.lastRUMViewEvent, viewEvent)
            expectation.fulfill()
        }

        core.send(message: .baggage(key: RUMBaggageKeys.viewEvent, value: viewEvent))

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    func testWhenRUMViewReset_thenItNotifiesNewCrashContext() throws {
        let expectation = self.expectation(description: "Notify new crash context")
        expectation.expectedFulfillmentCount = 2

        var viewEvent: AnyCodable? = AnyCodable(mockRandomAttributes())

        // When
        crashContextProvider.onCrashContextChange = {
            viewEvent = $0.lastRUMViewEvent
            expectation.fulfill()
        }

        core.send(message: .baggage(key: RUMBaggageKeys.viewEvent, value: viewEvent))
        core.send(message: .baggage(key: RUMBaggageKeys.viewReset, value: true))

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
        XCTAssertNil(viewEvent)
    }

    // MARK: - RUM Session State Integration

    func testWhenNewRUMSessionStateIsSentThroughMessageBus_thenItNotifiesNewCrashContext() throws {
        let expectation = self.expectation(description: "Notify new crash context")

        let sessionState: AnyCodable? = AnyCodable(mockRandomAttributes())

        // When
        crashContextProvider.onCrashContextChange = {
            DDAssertJSONEqual($0.lastRUMSessionState, sessionState)
            expectation.fulfill()
        }

        core.send(message: .baggage(key: RUMBaggageKeys.sessionState, value: sessionState))

        // Then
        waitForExpectations(timeout: 0.5, handler: nil)
    }

    // MARK: - Thread safety

    func testWhenContextIsWrittenAndReadFromDifferentThreads_itRunsAllOperationsSafely() {
        let viewEvent: RUMViewEvent = .mockRandom()
        let sessionState: RUMSessionState = .mockRandom()

        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { _ = self.crashContextProvider.currentCrashContext },
                { self.core.send(message: .context(.mockRandom())) },
                { self.core.send(message: .baggage(key: RUMBaggageKeys.viewReset, value: true)) },
                { self.core.send(message: .baggage(key: RUMBaggageKeys.viewEvent, value: viewEvent)) },
                { self.core.send(message: .baggage(key: RUMBaggageKeys.sessionState, value: sessionState)) },
            ],
            iterations: 50
        )

        // provider retains the core in its queue:
        // flush to release the core.
        crashContextProvider.flush()
        // swiftlint:enable opening_brace
    }
}
