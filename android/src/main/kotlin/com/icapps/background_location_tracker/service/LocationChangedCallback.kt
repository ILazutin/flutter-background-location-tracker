package com.icapps.background_location_tracker.service

import android.location.Location

interface LocationChangedCallback {
    fun onLocationChanged(position: Location?)
}