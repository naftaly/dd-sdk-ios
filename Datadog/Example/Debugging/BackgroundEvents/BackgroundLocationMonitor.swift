/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog
import CoreLocation

internal var backgroundLocationMonitor: BackgroundLocationMonitor?

/// Location monitor used in "Example" app for debugging and testing iOS SDK features in background.
internal class BackgroundLocationMonitor: NSObject, CLLocationManagerDelegate {
    private struct Constants {
        static let locationMonitoringUserDefaultsKey = "is-location-monitoring-started"
    }

    private let locationManager = CLLocationManager()

    /// Tells if location monitoring is started.
    /// This setting is preserved between application launches. Defaults to `false`.
    ///
    /// Note: `BackgroundLocationMonitor` can be started independently from receiving location monitoring authorization status.
    /// Even if this value is `true`, location updates might not be delivered due to restricted or denied status.
    private(set) var isStarted: Bool {
        get { UserDefaults.standard.bool(forKey: Constants.locationMonitoringUserDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.locationMonitoringUserDefaultsKey) }
    }

    /// Current authorization status for location monitoring.
    var currentAuthorizationStatus: String { authorizationStatusDescription(for: locationManager) }

    /// Notifies change of authorization status for location monitoring.
    var onAuthorizationStatusChange: ((String) -> Void)? = nil

    override init() {
        super.init()
        if isStarted {
            // If location monitoring was enabled in previous app session, here we start it for current session.
            // This will keep location tracking when the app is woken up in background due to significant location change.
            startMonitoring()
        }
    }

    func startMonitoring() {
        logger.debug("Starting 'BackgroundLocationMonitor' with authorizationStatus: '\(authorizationStatusDescription(for: locationManager))'")

        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            locationManager.delegate = self
            locationManager.allowsBackgroundLocationUpdates = true

            locationManager.requestAlwaysAuthorization()
            locationManager.startMonitoringSignificantLocationChanges()
            isStarted = true
        } else {
            Global.rum.addError(message: "Significant location changes monitoring is not available")
        }
    }

    func stopMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
        isStarted = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = authorizationStatusDescription(for: locationManager)
        logger.debug("Changed 'BackgroundLocationMonitor' authorizationStatus: '\(status)'")
        onAuthorizationStatusChange?(status)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let recentLocation = locations.last else {
            Global.rum.addError(message: "Received update with no locations")
            return
        }

        logger.debug(
            "Location changed at \(recentLocation.timestamp)",
            attributes: [
                "latitude": recentLocation.coordinate.latitude,
                "longitude": recentLocation.coordinate.longitude,
                "speed": recentLocation.speed,
            ]
        )

        Global.rum.addUserAction(
            type: .custom,
            name: "Location changed at \(recentLocation.timestamp)",
            attributes: [
                "latitude": recentLocation.coordinate.latitude,
                "longitude": recentLocation.coordinate.longitude,
                "speed": recentLocation.speed,
            ]
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError {
            if error.code == .denied {
                manager.stopMonitoringSignificantLocationChanges()
            }
            logger.error("Location manager failed with CLError (error.code: \(error.code)", error: error)
            Global.rum.addError(message: "Location manager failed with CLError (error.code: \(error.code)")
        } else {
            logger.error("Location manager failed", error: error)
            Global.rum.addError(error: error)
        }
    }

    // MARK: - Helpers

    private func authorizationStatusDescription(for manager: CLLocationManager) -> String {
        if #available(iOS 14.0, *) {
            switch locationManager.authorizationStatus {
            case .authorizedAlways: return "authorizedAlways"
            case .notDetermined: return "notDetermined"
            case .restricted: return "restricted"
            case .denied: return "denied"
            case .authorizedWhenInUse: return "authorizedWhenInUse"
            @unknown default: return "unrecognized (sth new)"
            }
        } else {
            return "unavailable prior to iOS 14.0"
        }
    }
}