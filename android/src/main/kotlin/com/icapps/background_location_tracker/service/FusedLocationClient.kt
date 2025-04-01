package com.icapps.background_location_tracker.service

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.os.Looper
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.LocationSettingsRequest
import com.google.android.gms.location.Priority
import com.icapps.background_location_tracker.utils.SharedPrefsUtil

class FusedLocationClient(
    private val context: Context
) : LocationClient {
    /**
     * Callback for changes in location.
     */
    private var locationCallback: LocationCallback? = null
    private var fusedLocationClient: FusedLocationProviderClient = LocationServices.getFusedLocationProviderClient(context)

    override fun startLocationUpdates(callback: LocationChangedCallback, onError: ErrorCallback) {
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                super.onLocationResult(locationResult)
                callback.onLocationChanged(locationResult.lastLocation)
            }
        }

        val locationRequest = createLocationRequest()
        val settingsRequest: LocationSettingsRequest =
            buildLocationSettingsRequest(locationRequest)

        val settingsClient = LocationServices.getSettingsClient(context)
        settingsClient.checkLocationSettings(settingsRequest)
            .addOnSuccessListener {
                resp -> requestLocationUpdates(locationRequest, locationCallback!!)
            }
            .addOnFailureListener {
                e -> onError.onError(context, e)
            }
    }

    override fun stopLocationUpdates() {
        if (locationCallback != null) {
            fusedLocationClient.removeLocationUpdates(locationCallback!!)
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestLocationUpdates(locationRequest: LocationRequest, locationCallback: LocationCallback) {
        fusedLocationClient.requestLocationUpdates(locationRequest, locationCallback, Looper.myLooper())
    }

    @SuppressLint("MissingPermission")
    override fun getLastLocation(callback: LocationChangedCallback, errorCallback: ErrorCallback) {
        fusedLocationClient.lastLocation.addOnSuccessListener {
            location -> callback.onLocationChanged(location)
        }.addOnFailureListener {
            error -> errorCallback.onError(context, error)
        }
    }

    private fun createLocationRequest(): LocationRequest {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return buildLocationRequestDeprecated()
        }

        val interval = SharedPrefsUtil.trackingInterval(context)
        val distanceFilter = SharedPrefsUtil.distanceFilter(context)

        val builder = LocationRequest.Builder(interval)
        builder.setPriority(Priority.PRIORITY_HIGH_ACCURACY)
//        builder.setMinUpdateIntervalMillis(interval / 2)
        builder.setMinUpdateDistanceMeters(distanceFilter)

        return builder.build()
    }

    @SuppressWarnings("deprecation")
    private fun buildLocationRequestDeprecated(): LocationRequest {
        val locationRequest = LocationRequest.create()

        val interval = SharedPrefsUtil.trackingInterval(context)
        val distanceFilter = SharedPrefsUtil.distanceFilter(context)

        locationRequest.setInterval(interval)
        locationRequest.setFastestInterval(interval / 2)
        locationRequest.setPriority(Priority.PRIORITY_HIGH_ACCURACY)
        locationRequest.setSmallestDisplacement(distanceFilter)

        return locationRequest
    }

    private fun buildLocationSettingsRequest(
        locationRequest: LocationRequest
    ): LocationSettingsRequest {
        val builder = LocationSettingsRequest.Builder()
        builder.addLocationRequest(locationRequest)

        return builder.build()
    }
}