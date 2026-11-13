package com.example.bluetooth_lab

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CHANNEL = "bluetooth.messenger/channel"
    private val EVENT_CHANNEL = "bluetooth.messenger/events"

    private val SERVICE_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private val REQUEST_BLUETOOTH_PERMISSIONS = 1
    private val REQUEST_ENABLE_BT = 2

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var clientSocket: BluetoothSocket? = null
    private var inputStream: InputStream? = null
    private var outputStream: OutputStream? = null
    private var connectThread: Thread? = null
    private var readThread: Thread? = null
    @Volatile private var isConnected = false
    @Volatile private var connectedAddress: String? = null
    @Volatile private var connectedName: String? = null

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val bluetoothManager = getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        if (bluetoothAdapter == null) {
            android.util.Log.e("BTMessenger", "Device doesn't support Bluetooth")
        }
        android.util.Log.d("BTMessenger", "Android SDK: " + Build.VERSION.SDK_INT)
    }

    override fun onDestroy() {
        super.onDestroy()
        closeConnection()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initializeBluetooth" -> result.success(initializeBluetooth())

                    "sendMessage" -> {
                        val msg = call.argument<String>("message")
                        if (msg != null) result.success(sendMessage(msg))
                        else result.error("INVALID_ARGUMENT", "Message is null", null)
                    }

                    "getPairedDevices" -> {
                        result.success(getPairedDevices())
                    }

                    "connectToDevice" -> {
                        val address = call.argument<String>("address")
                        if (address == null) {
                            result.error("INVALID_ARGUMENT", "address is null", null)
                        } else {
                            connectToDevice(address)
                            result.success(true)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }


    private fun hasBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADMIN) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestBluetoothPermissions() {
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
        } else {
            arrayOf(Manifest.permission.BLUETOOTH, Manifest.permission.BLUETOOTH_ADMIN)
        }
        ActivityCompat.requestPermissions(this, permissions, REQUEST_BLUETOOTH_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_BLUETOOTH_PERMISSIONS) {
            if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                android.util.Log.d("BTMessenger", "Bluetooth permissions granted")
                initializeBluetooth()
            } else {
                sendEvent(mapOf("type" to "error", "message" to "Bluetooth permissions required"))
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_ENABLE_BT) {
            if (resultCode == RESULT_OK) initializeBluetooth()
            else sendEvent(mapOf("type" to "error", "message" to "Bluetooth must be enabled"))
        }
    }


    private fun initializeBluetooth(): Boolean {
        android.util.Log.d("BTMessenger", "Initializing Bluetooth...")

        if (bluetoothAdapter == null) {
            sendEvent(mapOf("type" to "error", "message" to "Bluetooth not supported"))
            return false
        }

        if (bluetoothAdapter?.isEnabled != true) {
            val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT)
                    == PackageManager.PERMISSION_GRANTED
                ) {
                    startActivityForResult(enableBtIntent, REQUEST_ENABLE_BT)
                } else {
                    requestBluetoothPermissions()
                }
            } else {
                startActivityForResult(enableBtIntent, REQUEST_ENABLE_BT)
            }
            return false
        }

        if (!hasBluetoothPermissions()) {
            requestBluetoothPermissions()
            return false
        }

        if (isConnected) {
            sendEvent(
                mapOf(
                    "type" to "connection",
                    "connected" to true,
                    "device" to connectedName,
                    "address" to connectedAddress
                )
            )
            return true
        }

        connectToPC()
        return true
    }


    private fun getPairedDevices(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        try {
            val adapter = bluetoothAdapter ?: return list
            val paired = adapter.bondedDevices ?: return list
            val cur = if (isConnected) connectedAddress else null
            for (device in paired) {
                val name = try {
                    device.name ?: "Unknown"
                } catch (e: SecurityException) {
                    "Unknown"
                }
                val address = device.address ?: ""
                list.add(
                    mapOf(
                        "name" to name,
                        "address" to address,
                        "connected" to (cur != null && cur == address)
                    )
                )
            }
        } catch (e: SecurityException) {
            android.util.Log.e("BTMessenger", "SecurityException in getPairedDevices: " + e.message)
        } catch (e: Exception) {
            android.util.Log.e("BTMessenger", "Exception in getPairedDevices: " + e.message)
        }
        return list
    }


    private fun connectToDevice(address: String) {
        connectThread?.interrupt()
        connectThread = thread(start = true) {
            try {
                android.util.Log.d("BTMessenger", "connectToDevice: " + address)
                if (isConnected) {
                    closeConnection()
                    try { Thread.sleep(200) } catch (_: InterruptedException) {}
                }
                val adapter = bluetoothAdapter ?: return@thread
                val device: BluetoothDevice
                try {
                    device = adapter.getRemoteDevice(address)
                } catch (e: Exception) {
                    sendEvent(mapOf("type" to "error", "message" to "Invalid address: " + address))
                    return@thread
                }
                if (!tryConnect(device)) {
                    val dn = try { device.name } catch (_: SecurityException) { address }
                    sendEvent(mapOf("type" to "error", "message" to "Failed to connect to " + dn))
                }
            } catch (e: Exception) {
                android.util.Log.e("BTMessenger", "connectToDevice error: " + e.message, e)
                sendEvent(mapOf("type" to "error", "message" to "Connection error: " + e.message))
            }
        }
    }

    private fun connectToPC() {
        connectThread?.interrupt()
        connectThread = thread(start = true) {
            android.util.Log.d("BTMessenger", "Connecting to PC...")
            try {
                sendEvent(mapOf("type" to "connection", "connected" to false, "message" to "Searching for PC..."))

                try {
                    bluetoothAdapter?.cancelDiscovery()
                } catch (_: SecurityException) {}

                val pairedDevices = bluetoothAdapter?.bondedDevices
                android.util.Log.d("BTMessenger", "Found " + (pairedDevices?.size ?: 0) + " paired devices")

                if (pairedDevices.isNullOrEmpty()) {
                    sendEvent(mapOf("type" to "error", "message" to "No paired devices. Pair your PC first."))
                    return@thread
                }

                for (device in pairedDevices) {
                    if (isConnected) break
                    if (tryConnect(device)) break
                }

                if (!isConnected) {
                    android.util.Log.e("BTMessenger", "Could not connect to any paired device")
                    sendEvent(mapOf("type" to "error", "message" to "No PC found. Make sure PC script is running and devices are paired."))
                }
            } catch (e: Exception) {
                android.util.Log.e("BTMessenger", "Error connecting: " + e.message, e)
                sendEvent(mapOf("type" to "error", "message" to "Connection error: " + e.message))
            }
        }
    }

    private fun tryConnect(device: BluetoothDevice): Boolean {
        if (isConnected) return true

        val dname = try { device.name ?: "Unknown" } catch (_: SecurityException) { "Unknown" }
        val daddr = device.address
        android.util.Log.d("BTMessenger", "Trying to connect to: " + dname + " (" + daddr + ")")

        var socket: BluetoothSocket? = null
        try {
            socket = device.createRfcommSocketToServiceRecord(SERVICE_UUID)
            socket.connect()
            clientSocket = socket
            inputStream = socket.inputStream
            outputStream = socket.outputStream
            isConnected = true
            connectedAddress = daddr
            connectedName = dname
            android.util.Log.d("BTMessenger", "Connected to: " + dname + " via UUID")
            sendEvent(mapOf("type" to "connection", "connected" to true, "device" to dname, "address" to daddr))
            startReadThread()
            return true
        } catch (e: IOException) {
            android.util.Log.d("BTMessenger", "UUID method failed for " + dname + ": " + e.message)
            try { socket?.close() } catch (_: Exception) {}
        }

        socket = null
        try {
            socket = device.createInsecureRfcommSocketToServiceRecord(SERVICE_UUID)
            socket.connect()
            clientSocket = socket
            inputStream = socket.inputStream
            outputStream = socket.outputStream
            isConnected = true
            connectedAddress = daddr
            connectedName = dname
            android.util.Log.d("BTMessenger", "Connected to: " + dname + " via insecure")
            sendEvent(mapOf("type" to "connection", "connected" to true, "device" to dname, "address" to daddr))
            startReadThread()
            return true
        } catch (e: IOException) {
            android.util.Log.d("BTMessenger", "Insecure method failed for " + dname + ": " + e.message)
            try { socket?.close() } catch (_: Exception) {}
        }
        return false
    }


    private fun startReadThread() {
        readThread = thread(start = true) {
            val buffer = ByteArray(1024)
            var errors = 0
            val maxErrors = 3
            android.util.Log.d("BTMessenger", "Read thread started")

            while (isConnected && !Thread.currentThread().isInterrupted) {
                try {
                    val n = inputStream?.read(buffer) ?: -1
                    if (n > 0) {
                        errors = 0
                        val msg = String(buffer, 0, n, Charsets.UTF_8).trim()
                        if (msg.isNotEmpty()) {
                            android.util.Log.d("BTMessenger", "Received: " + msg)
                            sendEvent(mapOf("type" to "message", "data" to msg))
                        }
                    } else if (n < 0) {
                        android.util.Log.d("BTMessenger", "Connection closed by PC")
                        mainHandler.post { closeConnection() }
                        break
                    }
                } catch (e: IOException) {
                    errors++
                    android.util.Log.e("BTMessenger", "Read error (" + errors + "/" + maxErrors + "): " + e.message)
                    if (errors >= maxErrors) {
                        mainHandler.post { closeConnection() }
                        break
                    } else {
                        try { Thread.sleep(100) } catch (_: InterruptedException) { break }
                    }
                } catch (e: Exception) {
                    android.util.Log.e("BTMessenger", "Unexpected error: " + e.message, e)
                    mainHandler.post { closeConnection() }
                    break
                }
            }
            android.util.Log.d("BTMessenger", "Read thread exiting")
        }
    }

    private fun sendMessage(message: String): Boolean {
        if (!isConnected || outputStream == null) {
            android.util.Log.e("BTMessenger", "Cannot send - not connected")
            return false
        }
        return try {
            val bytes = (message + "\n").toByteArray(Charsets.UTF_8)
            outputStream?.write(bytes)
            outputStream?.flush()
            android.util.Log.d("BTMessenger", "Sent: " + message)
            true
        } catch (e: IOException) {
            android.util.Log.e("BTMessenger", "Error sending: " + e.message)
            closeConnection()
            false
        }
    }

    private fun closeConnection() {
        isConnected = false
        val wasName = connectedName
        connectedAddress = null
        connectedName = null
        sendEvent(mapOf("type" to "connection", "connected" to false, "device" to wasName))

        readThread?.interrupt(); readThread = null
        connectThread?.interrupt(); connectThread = null

        try { inputStream?.close() } catch (_: IOException) {}
        try { outputStream?.close() } catch (_: IOException) {}
        try { clientSocket?.close() } catch (_: IOException) {}

        inputStream = null
        outputStream = null
        clientSocket = null
        android.util.Log.d("BTMessenger", "Connection closed")
    }

    private fun sendEvent(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }
}