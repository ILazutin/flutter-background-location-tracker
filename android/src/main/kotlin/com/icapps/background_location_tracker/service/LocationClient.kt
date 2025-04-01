package com.icapps.background_location_tracker.service

interface LocationClient {
    fun startLocationUpdates(callback: LocationChangedCallback, onError: ErrorCallback)
    fun stopLocationUpdates()
    fun getLastLocation(callback: LocationChangedCallback, errorCallback: ErrorCallback)
}