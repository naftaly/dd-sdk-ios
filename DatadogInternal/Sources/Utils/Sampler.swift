/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Good number for Knuth hashing (large, prime, fit in 64 bit long)
internal let SAMPLER_HASHER: UInt64 = 1_111_111_111_111_111_111
internal let MAX_ID: UInt64 = 0xFFFFFFFFFFFFFFFF

/// Protocol for determining sampling decisions.
public protocol Sampling {
    /// Determines whether sampling should be performed.
    ///
    /// - Returns: A boolean value indicating whether sampling should occur.
    ///            `true` if the sample should be kept, `false` if it should be dropped.
    func sample() -> Bool
}

/// Sampler, deciding if events should be sent do Datadog or dropped.
public struct Sampler: Sampling {
    /// Value between `0.0` and `100.0`, where `0.0` means NO event will be sent and `100.0` means ALL events will be sent.
    public let samplingRate: Float

    public init(samplingRate: Float) {
        self.samplingRate = max(0, min(100, samplingRate))
    }

    /// Based on the sampling rate, it returns random value deciding if an event should be "sampled" or not.
    /// - Returns: `true` if event should be sent to Datadog and `false` if it should be dropped.
    public func sample() -> Bool {
        return Float.random(in: 0.0..<100.0) < samplingRate
    }
}

/// A sampler that determines sampling decisions deterministically (the same each time).
internal struct DeterministicSampler: Sampling {
    /// Value between `0.0` and `100.0`, where `0.0` means NO event will be sent and `100.0` means ALL events will be sent.
    let samplingRate: Float
    /// Persisted sampling decision.
    private let shouldSample: Bool

    init(shouldSample: Bool, samplingRate: Float) {
        self.samplingRate = samplingRate
        self.shouldSample = shouldSample
    }

    init(baseId: UInt64, samplingRate: Float) {
        // We use overflow multiplication to create a "randomized" hash based on the input id
        let hash = baseId &* SAMPLER_HASHER
        let threshold = UInt64(Float(MAX_ID) * samplingRate / 100.0)
        self.samplingRate = samplingRate
        self.shouldSample = hash < threshold
    }

    func sample() -> Bool { shouldSample }
}
