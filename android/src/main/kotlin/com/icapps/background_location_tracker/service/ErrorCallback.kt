package com.icapps.background_location_tracker.service

import android.content.Context

interface ErrorCallback {
    fun onError(context: Context, e: Exception)
}