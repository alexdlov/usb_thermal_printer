package com.example.usb_thermal_printer

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class UsbThermalPrinterPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    
    private var usbManager: UsbManager? = null
    private var connection: UsbDeviceConnection? = null
    private var endpoint: UsbEndpoint? = null
    
    companion object {
        private const val CHANNEL_NAME = "usb_thermal_printer"
        private const val EVENT_CHANNEL_NAME = "$CHANNEL_NAME/events"
        private const val ACTION_USB_PERMISSION = "$CHANNEL_NAME.USB_PERMISSION"
    }
    
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENT_CHANNEL_NAME)
        
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        
        usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        
        // Register USB permission receiver
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        context.registerReceiver(usbReceiver, filter)
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        
        try {
            context.unregisterReceiver(usbReceiver)
        } catch (e: Exception) {
            // Already unregistered
        }
        
        connection?.close()
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getDevices" -> getDevices(result)
            "hasPermission" -> {
                val vendorId = call.argument<Int>("vendorId") ?: 0
                val productId = call.argument<Int>("productId") ?: 0
                hasPermission(vendorId, productId, result)
            }
            "requestPermission" -> {
                val vendorId = call.argument<Int>("vendorId") ?: 0
                val productId = call.argument<Int>("productId") ?: 0
                requestPermission(vendorId, productId, result)
            }
            "connect" -> {
                val vendorId = call.argument<Int>("vendorId") ?: 0
                val productId = call.argument<Int>("productId") ?: 0
                connectToPrinter(vendorId, productId, result)
            }
            "disconnect" -> disconnect(result)
            "print" -> {
                val data = call.argument<List<Int>>("data") ?: emptyList()
                printData(data, result)
            }
            "isConnected" -> result.success(connection != null && endpoint != null)
            else -> result.notImplemented()
        }
    }
    
    private fun getDevices(result: Result) {
        try {
            val deviceList = usbManager?.deviceList ?: emptyMap()
            val devices = deviceList.values.map { device ->
                mapOf(
                    "vendorId" to device.vendorId,
                    "productId" to device.productId,
                    "deviceName" to device.deviceName,
                    "productName" to (device.productName ?: "Unknown"),
                    "manufacturerName" to (device.manufacturerName ?: "Unknown")
                )
            }
            result.success(devices)
        } catch (e: Exception) {
            result.error("GET_DEVICES_ERROR", e.message, null)
        }
    }
    
    private fun hasPermission(vendorId: Int, productId: Int, result: Result) {
        val device = findDevice(vendorId, productId)
        if (device == null) {
            result.success(false)
            return
        }
        result.success(usbManager?.hasPermission(device) ?: false)
    }
    
    private fun requestPermission(vendorId: Int, productId: Int, result: Result) {
        val device = findDevice(vendorId, productId)
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Device not found", null)
            return
        }
        
        if (usbManager?.hasPermission(device) == true) {
            result.success(true)
            return
        }
        
        // Store result to be called when permission is granted/denied
        pendingPermissionResult = result
        
        val permissionIntent = PendingIntent.getBroadcast(
            context, 
            0, 
            Intent(ACTION_USB_PERMISSION), 
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )
        usbManager?.requestPermission(device, permissionIntent)
    }
    
    private fun connectToPrinter(vendorId: Int, productId: Int, result: Result) {
        val device = findDevice(vendorId, productId)
        if (device == null) {
            result.success(false)
            return
        }
        
        if (usbManager?.hasPermission(device) == true) {
            val connected = connectToDevice(device)
            result.success(connected)
        } else {
            // Store pending connection for when permission is granted
            pendingConnectResult = result
            pendingConnectDevice = device
            
            val permissionIntent = PendingIntent.getBroadcast(
                context, 
                0, 
                Intent(ACTION_USB_PERMISSION), 
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
            )
            usbManager?.requestPermission(device, permissionIntent)
        }
    }
    
    private fun connectToDevice(device: UsbDevice): Boolean {
        try {
            connection = usbManager?.openDevice(device)
            if (connection == null) return false
            
            // Find the correct interface and endpoint
            for (i in 0 until device.interfaceCount) {
                val usbInterface = device.getInterface(i)
                if (connection?.claimInterface(usbInterface, true) == true) {
                    // Find bulk OUT endpoint
                    for (j in 0 until usbInterface.endpointCount) {
                        val ep = usbInterface.getEndpoint(j)
                        if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && 
                            ep.direction == UsbConstants.USB_DIR_OUT) {
                            endpoint = ep
                            sendConnectionEvent(true)
                            return true
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            sendConnectionEvent(false)
        }
        return false
    }
    
    private fun disconnect(result: Result) {
        connection?.close()
        connection = null
        endpoint = null
        sendConnectionEvent(false)
        result.success(true)
    }
    
    private fun printData(data: List<Int>, result: Result) {
        if (connection == null || endpoint == null) {
            result.success(false)
            return
        }
        
        try {
            val bytes = data.map { it.toByte() }.toByteArray()
            val transferResult = connection?.bulkTransfer(endpoint, bytes, bytes.size, 5000)
            result.success(transferResult != null && transferResult >= 0)
        } catch (e: Exception) {
            e.printStackTrace()
            result.success(false)
        }
    }
    
    private fun findDevice(vendorId: Int, productId: Int): UsbDevice? {
        val deviceList = usbManager?.deviceList ?: return null
        return deviceList.values.find { 
            it.vendorId == vendorId && it.productId == productId 
        }
    }
    
    private fun sendConnectionEvent(connected: Boolean) {
        eventSink?.success(mapOf("connected" to connected))
    }
    
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }
    
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
    
    private var pendingPermissionResult: Result? = null
    private var pendingConnectResult: Result? = null
    private var pendingConnectDevice: UsbDevice? = null
    
    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (ACTION_USB_PERMISSION == intent.action) {
                val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                
                // Handle permission-only result (when requestPermission was called directly)
                if (pendingPermissionResult != null && pendingConnectResult == null) {
                    pendingPermissionResult?.success(granted)
                    pendingPermissionResult = null
                }
                
                // Handle auto-connect after permission request from connectToPrinter
                if (pendingConnectResult != null) {
                    if (granted && device != null) {
                        val connected = connectToDevice(device)
                        pendingConnectResult?.success(connected)
                    } else {
                        pendingConnectResult?.success(false)
                    }
                    pendingConnectResult = null
                    pendingConnectDevice = null
                }
            }
        }
    }
}