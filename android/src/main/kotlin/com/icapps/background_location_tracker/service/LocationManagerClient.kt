package com.icapps.background_location_tracker.service

import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import androidx.core.location.LocationListenerCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.location.LocationRequestCompat
import com.google.android.gms.location.Priority
import com.icapps.background_location_tracker.utils.SharedPrefsUtil

class LocationManagerClient(
    private val context: Context
) : LocationClient, LocationListenerCompat {
    private val locationManager: LocationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var locationCallback: LocationChangedCallback? = null
    private var errorCallback: ErrorCallback? = null
    private var currentBestLocation: Location? = null
    private var currentLocationProvider: String? = null
    private var isListening: Boolean = false

    companion object {
        private const val TWO_MINUTES: Long = 120000
    }

    @SuppressLint("MissingPermission")
    override fun startLocationUpdates(callback: LocationChangedCallback, onError: ErrorCallback) {
        if (!checkLocationService(context)) {
            onError.onError(context, NoSuchElementException("service disabled"))
            return
        }

        currentLocationProvider =
            determineProvider(this.locationManager, Priority.PRIORITY_HIGH_ACCURACY)
        if (currentLocationProvider == null) {
            onError.onError(context, NoSuchElementException("no available providers"))
            return
        }

        locationCallback = callback
        errorCallback = onError

        val locationRequest = createLocationRequest()
        isListening = true
        LocationManagerCompat.requestLocationUpdates(
            locationManager,
            currentLocationProvider!!,
            locationRequest,
            this,
            Looper.getMainLooper()
        )
    }

    override fun stopLocationUpdates() {
        isListening = false
        locationManager.removeUpdates(this)
    }

    override fun getLastLocation(callback: LocationChangedCallback, errorCallback: ErrorCallback) {
        var bestLocation: Location? = null

        for (provider in locationManager.getProviders(true)) {
            @SuppressLint("MissingPermission") val location = locationManager.getLastKnownLocation(
                provider!!
            )

            if (location != null && isBetterLocation(
                    location,
                    bestLocation
                )
            ) {
                bestLocation = location
            }
        }

        callback.onLocationChanged(bestLocation)
    }

    private fun createLocationRequest(): LocationRequestCompat {
        val interval = SharedPrefsUtil.trackingInterval(context)
        val distanceFilter = SharedPrefsUtil.distanceFilter(context)

        val builder = LocationRequestCompat.Builder(interval)
        builder.setQuality(LocationRequestCompat.QUALITY_HIGH_ACCURACY)
        builder.setMinUpdateIntervalMillis(interval)
        builder.setMinUpdateDistanceMeters(distanceFilter)

        return builder.build()
    }

    private fun isBetterLocation(location: Location, bestLocation: Location?): Boolean {
        if (bestLocation == null) return true

        val timeDelta = location.time - bestLocation.time
        val isSignificantlyNewer: Boolean = timeDelta > TWO_MINUTES
        val isSignificantlyOlder: Boolean = timeDelta < -TWO_MINUTES
        val isNewer = timeDelta > 0

        if (isSignificantlyNewer) return true

        if (isSignificantlyOlder) return false

        val accuracyDelta = (location.accuracy - bestLocation.accuracy).toInt().toFloat()
        val isLessAccurate = accuracyDelta > 0
        val isMoreAccurate = accuracyDelta < 0
        val isSignificantlyLessAccurate = accuracyDelta > 200

        var isFromSameProvider = false
        if (location.provider != null) {
            isFromSameProvider = location.provider == bestLocation.provider
        }

        if (isMoreAccurate) return true

        if (isNewer && !isLessAccurate) return true

        if (isNewer && !isSignificantlyLessAccurate && isFromSameProvider) return true

        return false
    }

    private fun determineProvider(
        locationManager: LocationManager,
        accuracy: Int
    ): String? {
        val enabledProviders = locationManager.getProviders(true)

        return if (accuracy == Priority.PRIORITY_PASSIVE) {
            LocationManager.PASSIVE_PROVIDER
        } else if (enabledProviders.contains(LocationManager.FUSED_PROVIDER) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            LocationManager.FUSED_PROVIDER
        } else if (enabledProviders.contains(LocationManager.GPS_PROVIDER)) {
            LocationManager.GPS_PROVIDER
        } else if (enabledProviders.contains(LocationManager.NETWORK_PROVIDER)) {
            LocationManager.NETWORK_PROVIDER
        } else if (enabledProviders.isNotEmpty()) {
            enabledProviders[0]
        } else {
            null
        }
    }

    override fun onLocationChanged(location: Location) {
        if (isBetterLocation(location, currentBestLocation)) {
            currentBestLocation = location
            locationCallback?.onLocationChanged(location)
        }
    }

    @Suppress("DEPRECATION", "RedundantSuppression")
    @TargetApi(28)
    override fun onStatusChanged(provider: String, status: Int, extras: Bundle?) {
        if (status == android.location.LocationProvider.OUT_OF_SERVICE) {
            onProviderDisabled(provider)
        }
    }

    override fun onProviderEnabled(provider: String) {
        locationCallback ?: return
        errorCallback ?: return
        if (currentLocationProvider == null && !isListening) {
            startLocationUpdates(locationCallback!!, errorCallback!!)
        }
    }

    override fun onProviderDisabled(provider: String) {
        if (provider == this.currentLocationProvider) {
            if (isListening) {
                locationManager.removeUpdates(this)
            }

            if (this.errorCallback != null) {
                errorCallback!!.onError(context, Exception("provider disabled"))
            }

            this.currentLocationProvider = null
        }
    }

    private fun checkLocationService(context: Context): Boolean {
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val gpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
        val networkEnabled = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        return gpsEnabled || networkEnabled
    }
}