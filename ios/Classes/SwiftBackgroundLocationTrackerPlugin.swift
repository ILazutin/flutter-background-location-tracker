import Flutter
import UIKit
import CoreLocation

public class SwiftBackgroundLocationTrackerPlugin: FlutterPluginAppLifeCycleDelegate, ObservableObject {
    
    static let identifier = "com.icapps.background_location_tracker"
    
    private static let flutterThreadLabelPrefix = "\(identifier).BackgroundLocationTracker"
    
    private static var foregroundChannel: ForegroundChannel? = nil
    private static var backgroundMethodChannel: FlutterMethodChannel? = nil
    
    private static var flutterEngine: FlutterEngine? = nil
    private static var hasRegisteredPlugins = false
    private static var initializedBackgroundCallbacks = false
    private static var initializedBackgroundCallbacksStarted = false
    private static var locationData: [String: Any]? = nil
    
    // This will store the plugin that registered engines
    private static var pluginRegistrants: [(FlutterEngine) -> Void] = []
    
    private let locationManager = LocationManager.shared()
}

extension SwiftBackgroundLocationTrackerPlugin: @preconcurrency FlutterPlugin {
    
    @objc
    public static func setPluginRegistrantCallback(_ callback: @escaping FlutterPluginRegistrantCallback) {
        // Store the callback in our new pluginRegistrants array
        pluginRegistrants.append(callback)
    }
    
    @MainActor public static func register(with registrar: FlutterPluginRegistrar) {
        CustomLogger.log(message: "handle register func")
        foregroundChannel = ForegroundChannel()
        let methodChannel = ForegroundChannel.createMethodChannel(binaryMessenger: registrar.messenger())
        let instance = SwiftBackgroundLocationTrackerPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        registrar.addApplicationDelegate(instance)
        
        startTracking(instance: instance)
    }
  
    @MainActor private static func startTracking(instance: SwiftBackgroundLocationTrackerPlugin) {
        if !(SharedPrefsUtil.isTracking() && SharedPrefsUtil.restartAfterKill()) {
            return
        }
        if #available(iOS 17.0, *) {
            let locationsHandler = LocationsHandler.shared
            locationsHandler.startLocationUpdates(callback: {location in
              sendLocationLiveUpdate(location: location)
            })
        } else {
            instance.locationManager.delegate = instance
            instance.locationManager.startUpdatingLocation()
        }
    }
  
    public static func sendLocationLiveUpdate(location: CLLocation?) {
        CustomLogger.log(message: "handle sendLocationLiveUpdate")
        guard let location = location else {
            CustomLogger.log(message: "No location ...")
            return
        }
    
        CustomLogger
            .log(
                message: "NEW LOCATION LIVE UPDATE: \(location.coordinate.latitude): \(location.coordinate.longitude)"
            )
    
        var locationData: [String: Any] = [
            "lat": location.coordinate.latitude,
            "lon": location.coordinate.longitude,
            "alt": location.altitude,
            "vertical_accuracy": location.verticalAccuracy,
            "horizontal_accuracy": location.horizontalAccuracy,
            "course": location.course,
            "course_accuracy": -1,
            "speed": location.speed,
            "speed_accuracy": location.speedAccuracy,
            "logging_enabled": SharedPrefsUtil.isLoggingEnabled(),
        ]
    
        if #available(iOS 13.4, *) {
            locationData["course_accuracy"] = location.courseAccuracy
        }
    
        if SwiftBackgroundLocationTrackerPlugin.initializedBackgroundCallbacks {
            CustomLogger
                .log(message: "INITIALIZED, ready to send location updates")
            SwiftBackgroundLocationTrackerPlugin
                .sendLocationupdate(locationData: locationData)
        } else {
            CustomLogger
                .log(message: "NOT YET INITIALIZED. Cache the location data")
            SwiftBackgroundLocationTrackerPlugin.locationData = locationData
        
            if !SwiftBackgroundLocationTrackerPlugin.initializedBackgroundCallbacksStarted {
                SwiftBackgroundLocationTrackerPlugin.initializedBackgroundCallbacksStarted = true
        
                guard let flutterEngine = SwiftBackgroundLocationTrackerPlugin.getFlutterEngine() else {
                    CustomLogger.log(message: "No Flutter engine available ...")
                    return
                }
                SwiftBackgroundLocationTrackerPlugin
                    .initBackgroundMethodChannel(flutterEngine: flutterEngine)
            }
        }
    }
    
    @MainActor public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        CustomLogger.log(message: "handle handle func")
        locationManager.delegate = self
        SwiftBackgroundLocationTrackerPlugin.foregroundChannel?
            .handle(call, result: result)
    }
    
    public static func getFlutterEngine()-> FlutterEngine? {
        CustomLogger.log(message: "handle getFlutterEngine")
        if flutterEngine == nil {
            let flutterEngine = FlutterEngine(name: flutterThreadLabelPrefix, project: nil, allowHeadlessExecution: true)
            
            guard let callbackHandle = SharedPrefsUtil.getCallbackHandle(),
                  let flutterCallbackInformation = FlutterCallbackCache.lookupCallbackInformation(callbackHandle) else {
                CustomLogger.log(message: "No flutter callback cache ...")
                return nil
            }
            let success = flutterEngine.run(withEntrypoint: flutterCallbackInformation.callbackName, libraryURI: flutterCallbackInformation.callbackLibraryPath)
            
            CustomLogger.log(message: "FlutterEngine.run returned `\(success)`")
            if success {
                // Run all the registered plugin registrants
                for registrant in pluginRegistrants {
                    registrant(flutterEngine)
                }
                self.flutterEngine = flutterEngine
            } else {
                CustomLogger.log(message: "FlutterEngine.run returned `false` we will cleanup the flutterEngine")
                flutterEngine.destroyContext()
            }
        }
        return flutterEngine
    }
    
    public static func initBackgroundMethodChannel(flutterEngine: FlutterEngine) {
        CustomLogger.log(message: "handle initBackgroundMethodChannel")
        if backgroundMethodChannel == nil {
            let backgroundMethodChannel = FlutterMethodChannel(name: SwiftBackgroundLocationTrackerPlugin.BACKGROUND_CHANNEL_NAME, binaryMessenger: flutterEngine.binaryMessenger)
            backgroundMethodChannel.setMethodCallHandler { (call, result) in
                switch call.method {
                case BackgroundMethods.initialized.rawValue:
                    initializedBackgroundCallbacks = true
                    if let data = SwiftBackgroundLocationTrackerPlugin.locationData {
                        CustomLogger.log(message: "Initialized with cached value, sending location update")
                        sendLocationupdate(locationData: data)
                    } else {
                        CustomLogger.log(message: "Initialized without cached value")
                    }
                    result(true)
                default:
                    CustomLogger.log(message: "Not implemented method -> \(call.method)")
                    result(FlutterMethodNotImplemented)
                }
            }
            self.backgroundMethodChannel = backgroundMethodChannel
        }
    }
    
    public static func sendLocationupdate(locationData: [String: Any]){
        CustomLogger.log(message: "handle sendLocationupdate with string of locationData")
        guard let backgroundMethodChannel = SwiftBackgroundLocationTrackerPlugin.backgroundMethodChannel else {
            CustomLogger.log(message: "No background channel available ...")
            return
        }
        backgroundMethodChannel.invokeMethod(BackgroundMethods.onLocationUpdate.rawValue, arguments: locationData, result: { flutterResult in
            CustomLogger.log(message: "Received result: \(flutterResult.debugDescription)")
        })
    }
}

fileprivate enum BackgroundMethods: String {
    case initialized = "initialized"
    case onLocationUpdate = "onLocationUpdate"
}

extension SwiftBackgroundLocationTrackerPlugin: CLLocationManagerDelegate {
    private static let BACKGROUND_CHANNEL_NAME = "com.icapps.background_location_tracker/background_channel"
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        CustomLogger.log(message: "handle locationManager delegate method")
        guard let location = locations.last else {
            CustomLogger.log(message: "No location ...")
            return
        }
        
        CustomLogger.log(message: "NEW LOCATION: \(location.coordinate.latitude): \(location.coordinate.longitude)")
        
        var locationData: [String: Any] = [
            "lat": location.coordinate.latitude,
            "lon": location.coordinate.longitude,
            "alt": location.altitude,
            "vertical_accuracy": location.verticalAccuracy,
            "horizontal_accuracy": location.horizontalAccuracy,
            "course": location.course,
            "course_accuracy": -1,
            "speed": location.speed,
            "speed_accuracy": location.speedAccuracy,
            "logging_enabled": SharedPrefsUtil.isLoggingEnabled(),
        ]
        
        if #available(iOS 13.4, *) {
            locationData["course_accuracy"] = location.courseAccuracy
        }
        
        if SwiftBackgroundLocationTrackerPlugin.initializedBackgroundCallbacks {
            CustomLogger.log(message: "INITIALIZED, ready to send location updates")
            SwiftBackgroundLocationTrackerPlugin.sendLocationupdate(locationData: locationData)
        } else {
            CustomLogger.log(message: "NOT YET INITIALIZED. Cache the location data")
            SwiftBackgroundLocationTrackerPlugin.locationData = locationData
            
            if !SwiftBackgroundLocationTrackerPlugin.initializedBackgroundCallbacksStarted {
                SwiftBackgroundLocationTrackerPlugin.initializedBackgroundCallbacksStarted = true
            
                guard let flutterEngine = SwiftBackgroundLocationTrackerPlugin.getFlutterEngine() else {
                    CustomLogger.log(message: "No Flutter engine available ...")
                    return
                }
                SwiftBackgroundLocationTrackerPlugin.initBackgroundMethodChannel(flutterEngine: flutterEngine)
            }
        }
    }
}
