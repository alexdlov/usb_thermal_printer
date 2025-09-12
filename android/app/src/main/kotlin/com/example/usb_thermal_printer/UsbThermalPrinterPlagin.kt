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
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentHashMap

class UsbThermalPrinterPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    
    private var usbManager: UsbManager? = null
    private val connections = ConcurrentHashMap<String, UsbConnection>()
    private var currentConnection: UsbConnection? = null
    
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
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
        
        // Register USB receiver
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(ACTION_USB_PERMISSION)
        }
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
        
        // Close all connections
        connections.values.forEach { it.close() }
        connections.clear()
        
        scope.cancel()
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
                val config = call.argument<Map<String, Any>>("config") ?: emptyMap()
                connect(vendorId, productId, config, result)
            }
            "disconnect" -> disconnect(result)
            "print" -> {
                val data = call.argument<List<Int>>("data") ?: emptyList()
                print(data, result)
            }
            "isConnected" -> result.success(currentConnection?.isConnected ?: false)
            else -> result.notImplemented()
        }
    }
    
    private fun getDevices(result: Result) {
        scope.launch {
            try {
                val devices = usbManager?.deviceList?.values?.map { device ->
                    mapOf(
                        "vendorId" to device.vendorId,
                        "productId" to device.productId,
                        "deviceName" to device.deviceName,
                        "productName" to device.productName,
                        "manufacturerName" to device.manufacturerName,
                        "serialNumber" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            device.serialNumber
                        } else {
                            null
                        }
                    )
                } ?: emptyList()
                
                withContext(Dispatchers.Main) {
                    result.success(devices)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("GET_DEVICES_ERROR", e.message, null)
                }
            }
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
            result.success(false)
            return
        }
        
        if (usbManager?.hasPermission(device) == true) {
            result.success(true)
            return
        }
        
        // Store result to be called when permission is granted
        pendingPermissionResults[device.deviceName] = result
        
        val permissionIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(ACTION_USB_PERMISSION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        usbManager?.requestPermission(device, permissionIntent)
    }
    
    private fun connect(vendorId: Int, productId: Int, config: Map<String, Any>, result: Result) {
        scope.launch {
            try {
                val device = findDevice(vendorId, productId)
                if (device == null) {
                    withContext(Dispatchers.Main) {
                        result.success(false)
                    }
                    return@launch
                }
                
                // Close existing connection
                currentConnection?.close()
                
                // Create new connection
                val connection = UsbConnection(
                    device = device,
                    usbManager = usbManager!!,
                    config = PrinterConfig.fromMap(config)
                )
                
                val connected = connection.connect()
                
                if (connected) {
                    currentConnection = connection
                    connections[device.deviceName] = connection
                    updateConnectionState(ConnectionState.CONNECTED)
                }
                
                withContext(Dispatchers.Main) {
                    result.success(connected)
                }
            } catch (e: Exception) {
                updateConnectionState(ConnectionState.DISCONNECTED)
                withContext(Dispatchers.Main) {
                    result.error("CONNECT_ERROR", e.message, null)
                }
            }
        }
    }
    
    private fun disconnect(result: Result) {
        scope.launch {
            try {
                currentConnection?.close()
                currentConnection = null
                updateConnectionState(ConnectionState.DISCONNECTED)
                
                withContext(Dispatchers.Main) {
                    result.success(true)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("DISCONNECT_ERROR", e.message, null)
                }
            }
        }
    }
    
    private fun print(data: List<Int>, result: Result) {
        scope.launch {
            try {
                val connection = currentConnection
                if (connection == null || !connection.isConnected) {
                    withContext(Dispatchers.Main) {
                        result.success(mapOf(
                            "type" to "failure",
                            "error" to "notConnected"
                        ))
                    }
                    return@launch
                }
                
                val startTime = System.currentTimeMillis()
                val bytesSent = connection.write(data.map { it.toByte() }.toByteArray())
                val duration = System.currentTimeMillis() - startTime
                
                withContext(Dispatchers.Main) {
                    if (bytesSent > 0) {
                        result.success(mapOf(
                            "type" to "success",
                            "bytesSent" to bytesSent,
                            "duration" to duration
                        ))
                    } else {
                        result.success(mapOf(
                            "type" to "failure",
                            "error" to "writeError"
                        ))
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "type" to "failure",
                        "error" to "unknown",
                        "message" to e.message
                    ))
                }
            }
        }
    }
    
    // Helper functions
    private fun findDevice(vendorId: Int, productId: Int): UsbDevice? {
        return usbManager?.deviceList?.values?.find {
            it.vendorId == vendorId && it.productId == productId
        }
    }
    
    private fun updateConnectionState(state: ConnectionState) {
        eventSink?.success(state.value)
    }
    
    // EventChannel.StreamHandler implementation
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }
    
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
    
    // USB Receiver
    private val pendingPermissionResults = ConcurrentHashMap<String, Result>()
    
    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    // Device attached, refresh device list
                    updateConnectionState(ConnectionState.DISCONNECTED)
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    if (device != null && connections.containsKey(device.deviceName)) {
                        connections[device.deviceName]?.close()
                        connections.remove(device.deviceName)
                        
                        if (currentConnection?.device?.deviceName == device.deviceName) {
                            currentConnection = null
                            updateConnectionState(ConnectionState.DISCONNECTED)
                        }
                    }
                }
                ACTION_USB_PERMISSION -> {
                    val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    
                    device?.let {
                        pendingPermissionResults[it.deviceName]?.success(granted)
                        pendingPermissionResults.remove(it.deviceName)
                    }
                }
            }
        }
    }
}

// Supporting classes
class UsbConnection(
    val device: UsbDevice,
    private val usbManager: UsbManager,
    private val config: PrinterConfig
) {
    private var connection: UsbDeviceConnection? = null
    private var endpoint: UsbEndpoint? = null
    
    val isConnected: Boolean
        get() = connection != null
    
    fun connect(): Boolean {
        try {
            connection = usbManager.openDevice(device)
            if (connection == null) return false
            
            // Find interface and endpoint
            for (i in 0 until device.interfaceCount) {
                val usbInterface = device.getInterface(i)
                
                if (connection?.claimInterface(usbInterface, true) == true) {
                    // Find bulk OUT endpoint
                    for (j in 0 until usbInterface.endpointCount) {
                        val ep = usbInterface.getEndpoint(j)
                        if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                            ep.direction == UsbConstants.USB_DIR_OUT) {
                            endpoint = ep
                            return true
                        }
                    }
                }
            }
            
            close()
            return false
        } catch (e: Exception) {
            close()
            throw e
        }
    }
    
    fun write(data: ByteArray): Int {
        val conn = connection ?: return -1
        val ep = endpoint ?: return -1
        
        return conn.bulkTransfer(ep, data, data.size, config.timeout)
    }
    
    fun close() {
        connection?.close()
        connection = null
        endpoint = null
    }
}

data class PrinterConfig(
    val baudRate: Int = 9600,
    val dataBits: Int = 8,
    val stopBits: Int = 1,
    val parity: Int = 0,
    val flowControl: Int = 0,
    val timeout: Int = 5000,
    val type: Int = 0
) {
    companion object {
        fun fromMap(map: Map<String, Any>): PrinterConfig {
            return PrinterConfig(
                baudRate = (map["baudRate"] as? Int) ?: 9600,
                dataBits = (map["dataBits"] as? Int) ?: 8,
                stopBits = (map["stopBits"] as? Int) ?: 1,
                parity = (map["parity"] as? Int) ?: 0,
                flowControl = (map["flowControl"] as? Int) ?: 0,
                timeout = (map["timeout"] as? Int) ?: 5000,
                type = (map["type"] as? Int) ?: 0
            )
        }
    }
}

enum class ConnectionState(val value: Int) {
    DISCONNECTED(0),
    CONNECTING(1),
    CONNECTED(2),
    DISCONNECTING(3)
}