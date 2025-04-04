import Flutter
import UIKit
import SwiftUI
import CoreLocation

// Shared state that manages the `CLLocationManager` and `CLBackgroundActivitySession`.
@available(iOS 17.0, *)
@MainActor public class LocationsHandler: ObservableObject {
    
    static let shared = LocationsHandler()  // Create a single, shared instance of the object.
    private let manager: CLLocationManager
    private var background: CLBackgroundActivitySession?
  
    @Published var lastLocation = CLLocation()
    @Published var isStationary = false
    @Published var trackingInterval: Double = 10
    @Published var distanceFilter: Double? = kCLDistanceFilterNone
    
    @Published
    var updatesStarted: Bool = UserDefaults.standard.bool(
        forKey: "liveUpdatesStarted"
    ) {
        didSet {
            UserDefaults.standard
                .set(updatesStarted, forKey: "liveUpdatesStarted")
        }
    }
    
    @Published
    var backgroundActivity: Bool = UserDefaults.standard.bool(
        forKey: "BGActivitySessionStarted"
    ) {
        didSet {
            CustomLogger
                .log(
                    message: "change backgroundActivity var to \(backgroundActivity)"
                )
            backgroundActivity ? self.background = CLBackgroundActivitySession() : self.background?
                .invalidate()
            UserDefaults.standard
                .set(backgroundActivity, forKey: "BGActivitySessionStarted")
        }
    }
    
    
    private init() {
        CustomLogger.log(message: "handle LocationsHandler.init")
        self.manager = CLLocationManager()  // Creating a location manager instance is safe to call here in `MainActor`.
    }
    
    func startLocationUpdates(callback: @escaping ((CLLocation?) -> Void)) {
        CustomLogger
            .log(message: "handle LocationsHandler.startLocationUpdates")
        if self.manager.authorizationStatus == .notDetermined {
            self.manager.requestAlwaysAuthorization()
        }
        self.trackingInterval = SharedPrefsUtil.trackingInterval()
        self.distanceFilter = SharedPrefsUtil.distanceFilter()
        CustomLogger.log(message: "Starting location updates")
        Task() {
            do {
                self.updatesStarted = true
                self.backgroundActivity = true
                let activityType = SharedPrefsUtil.activityType()
                let updates = CLLocationUpdate.liveUpdates(
                    self.activityTypeToLiveConfig(activityType: activityType)
                )
                for try await update in updates
                    .filter(
{locationUpdate in
    guard let location = locationUpdate.location else {
        return false
    }
    return await self.filterLocations(update: location)
})
                {
                    CustomLogger
                        .log(message: "handle LocationsHandler.liveUpdates")
                    if !self.updatesStarted {
                        break
                    }  // End location updates by breaking out of the loop.
                    if let loc = update.location {
                        self.lastLocation = loc
                        if #available(iOS 18.0, *) {
                            self.isStationary = update.stationary
                        } else {
                            self.isStationary = update.isStationary
                        }
                        callback(loc)
                    }
                }
            } catch {
                CustomLogger.log(message: "LocationsHandler. Could not start location updates")
            }
            return
        }
    }
    
    func stopLocationUpdates() {
        CustomLogger.log(message: "handle LocationsHandler.stopLocationUpdates")
        self.updatesStarted = false
        self.backgroundActivity = false
    }
  
    private func filterLocations(update: CLLocation) -> Bool {
        CustomLogger.log(message: "handle LocationsHandler.filterLocations")
        if update.timestamp < self.lastLocation.timestamp
            .addingTimeInterval(trackingInterval) {
            return false
        }
        
        let distanceThreshold = self.distanceFilter ?? kCLDistanceFilterNone
        if distanceThreshold > 0 {
            let distanceMoved = update.distance(from: self.lastLocation)
            if distanceMoved < distanceThreshold {
                return false
            }
        }
        
        return true
    }
    
    private func activityTypeToLiveConfig(activityType: CLActivityType) -> CLLocationUpdate.LiveConfiguration {
        switch (activityType) {
        case .other:
            return CLLocationUpdate.LiveConfiguration.default
        case .fitness:
            return CLLocationUpdate.LiveConfiguration.fitness
        case .otherNavigation:
            return CLLocationUpdate.LiveConfiguration.otherNavigation
        case .airborne:
            return CLLocationUpdate.LiveConfiguration.airborne
        case .automotiveNavigation:
            return CLLocationUpdate.LiveConfiguration.automotiveNavigation
        default:
            return CLLocationUpdate.LiveConfiguration.automotiveNavigation
        }
    }
}
