package com.example.mesh_message

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val methodName = "mesh/bluetooth"
    private val eventName = "mesh/events"

    private val serviceUUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef0")
    private val rxUUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef1")
    private val txUUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef2")
    private val cccdUUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    private lateinit var adapter: BluetoothAdapter
    private var advertiser: BluetoothLeAdvertiser? = null
    private var scanner: BluetoothLeScanner? = null
    private var gattServer: BluetoothGattServer? = null
    private var clientGatt: BluetoothGatt? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val connectedDevices = mutableMapOf<String, BluetoothDevice>()
    private val subscribers = mutableSetOf<String>()
    private val discoveredDevices = mutableSetOf<String>()

    private var scanCallback: ScanCallback? = null
    private var advertisingCallback: AdvertiseCallback? = null

    private fun emit(event: String, data: Any? = null) {
        runOnUiThread {
            eventSink?.success(mapOf("event" to event, "data" to data))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val manager = getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
        adapter = manager.adapter

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodName
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "requestPermissions" -> requestBluetoothPermissions(result)
                    "startServer" -> {
                        startServer()
                        result.success(true)
                    }
                    "stopServer" -> {
                        stopServer()
                        result.success(true)
                    }
                    "startScan" -> {
                        startScan()
                        result.success(true)
                    }
                    "stopScan" -> {
                        stopScan()
                        result.success(true)
                    }
                    "connect" -> {
                        val address = call.argument<String>("address")
                            ?: throw IllegalArgumentException("Device address missing")
                        connect(address)
                        result.success(true)
                    }
                    "send" -> {
                        val message = call.argument<String>("message") ?: ""
                        send(message)
                        result.success(true)
                    }
                    "disconnect" -> {
                        disconnect()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("BLUETOOTH_ERROR", e.message, null)
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun requestBluetoothPermissions(result: MethodChannel.Result) {
        val required = if (Build.VERSION.SDK_INT >= 31) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE
            )
        } else if (Build.VERSION.SDK_INT >= 23) {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        } else {
            emptyArray()
        }

        val missing = required.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }

        if (missing.isEmpty()) {
            result.success(true)
        } else {
            pendingPermissionResult = result
            requestPermissions(missing.toTypedArray(), 1001)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun startServer() {
        if (!adapter.isEnabled) throw IllegalStateException("Enable Bluetooth first")

        advertiser = adapter.bluetoothLeAdvertiser
            ?: throw IllegalStateException("BLE advertising unavailable")

        val manager = getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
        gattServer = manager.openGattServer(this, serverCallback)
            ?: throw IllegalStateException("Could not open GATT server")

        val service = BluetoothGattService(
            serviceUUID,
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        )

        val rx = BluetoothGattCharacteristic(
            rxUUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )

        val tx = BluetoothGattCharacteristic(
            txUUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )

        tx.addDescriptor(
            BluetoothGattDescriptor(
                cccdUUID,
                BluetoothGattDescriptor.PERMISSION_READ or
                    BluetoothGattDescriptor.PERMISSION_WRITE
            )
        )

        service.addCharacteristic(rx)
        service.addCharacteristic(tx)
        gattServer?.addService(service)
        emit("status", "Starting BLE server")
    }

    private fun startAdvertising() {
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(serviceUUID))
            .setIncludeDeviceName(false)
            .build()

        advertisingCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                emit("status", "Advertising as MeshMessage")
            }

            override fun onStartFailure(errorCode: Int) {
                emit("error", "Advertising failed: $errorCode")
            }
        }

        advertiser?.startAdvertising(settings, data, advertisingCallback)
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                startAdvertising()
            } else {
                emit("error", "GATT service registration failed: $status")
            }
        }

        override fun onConnectionStateChange(
            device: BluetoothDevice,
            status: Int,
            newState: Int
        ) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedDevices[device.address] = device
                emit("connected", device.address)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connectedDevices.remove(device.address)
                subscribers.remove(device.address)
                emit("disconnected", device.address)
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (characteristic.uuid != rxUUID || offset != 0) {
                if (responseNeeded) {
                    gattServer?.sendResponse(
                        device, requestId,
                        BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
                        0, null
                    )
                }
                return
            }

            if (responseNeeded) {
                gattServer?.sendResponse(
                    device, requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    0, null
                )
            }

            emit(
                "message",
                mapOf(
                    "from" to device.address,
                    "text" to value.toString(Charsets.UTF_8)
                )
            )
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (descriptor.uuid == cccdUUID) {
                if (value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) {
                    subscribers.add(device.address)
                } else {
                    subscribers.remove(device.address)
                }

                if (responseNeeded) {
                    gattServer?.sendResponse(
                        device, requestId,
                        BluetoothGatt.GATT_SUCCESS,
                        0, null
                    )
                }
            }
        }
    }

    private fun stopServer() {
        advertisingCallback?.let { advertiser?.stopAdvertising(it) }
        advertisingCallback = null
        gattServer?.close()
        gattServer = null
        connectedDevices.clear()
        subscribers.clear()
        emit("status", "Server stopped")
    }

    private fun startScan() {
        if (!adapter.isEnabled) throw IllegalStateException("Enable Bluetooth first")

        scanner = adapter.bluetoothLeScanner
            ?: throw IllegalStateException("BLE scanning unavailable")

        discoveredDevices.clear()

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(serviceUUID))
            .build()

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device
                if (discoveredDevices.add(device.address)) {
                    emit(
                        "device",
                        mapOf(
                            "name" to (device.name ?: "MeshMessage Device"),
                            "address" to device.address,
                            "rssi" to result.rssi
                        )
                    )
                }
            }

            override fun onScanFailed(errorCode: Int) {
                emit("error", "Scan failed: $errorCode")
            }
        }

        scanner?.startScan(listOf(filter), settings, scanCallback)
        emit("status", "Scanning for MeshMessage devices")
    }

    private fun stopScan() {
        scanCallback?.let { scanner?.stopScan(it) }
        scanCallback = null
        emit("status", "Scanning stopped")
    }

    private fun connect(address: String) {
        val device = adapter.getRemoteDevice(address)
        clientGatt?.close()
        clientGatt = device.connectGatt(
            this,
            false,
            clientCallback,
            BluetoothDevice.TRANSPORT_LE
        )
        emit("status", "Connecting to $address")
    }

    private val clientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(
            gatt: BluetoothGatt,
            status: Int,
            newState: Int
        ) {
            if (status == BluetoothGatt.GATT_SUCCESS &&
                newState == BluetoothProfile.STATE_CONNECTED
            ) {
                clientGatt = gatt
                emit("status", "Connected; discovering service")
                gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                emit("disconnected", "Remote device")
                gatt.close()
                if (clientGatt == gatt) clientGatt = null
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                emit("error", "Service discovery failed")
                return
            }

            val tx = gatt.getService(serviceUUID)?.getCharacteristic(txUUID)
            if (tx == null) {
                emit("error", "MeshMessage TX characteristic not found")
                return
            }

            gatt.setCharacteristicNotification(tx, true)
            val descriptor = tx.getDescriptor(cccdUUID)

            if (descriptor == null) {
                emit("error", "Notification descriptor missing")
                return
            }

            if (Build.VERSION.SDK_INT >= 33) {
                gatt.writeDescriptor(
                    descriptor,
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                )
            } else {
                @Suppress("DEPRECATION")
                run {
                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    gatt.writeDescriptor(descriptor)
                }
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int
        ) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                emit("connected", "Notifications enabled")
            } else {
                emit("error", "Notification setup failed: $status")
            }
        }

        @Deprecated("Legacy callback")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (characteristic.uuid == txUUID) {
                emit("message", characteristic.value?.toString(Charsets.UTF_8) ?: "")
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            if (characteristic.uuid == txUUID) {
                emit("message", value.toString(Charsets.UTF_8))
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                emit("sent", "GATT write acknowledged")
            } else {
                emit("error", "GATT write failed: $status")
            }
        }
    }

    private fun send(message: String) {
        val bytes = message.toByteArray(Charsets.UTF_8)

        if (bytes.isEmpty() || bytes.size > 20) {
            throw IllegalArgumentException("Message must be 1–20 UTF-8 bytes in v0.1")
        }

        val gatt = clientGatt

        if (gatt != null) {
            val rx = gatt.getService(serviceUUID)?.getCharacteristic(rxUUID)
                ?: throw IllegalStateException("Remote RX characteristic unavailable")

            if (Build.VERSION.SDK_INT >= 33) {
                val status = gatt.writeCharacteristic(
                    rx,
                    bytes,
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                )
                if (status != BluetoothStatusCodes.SUCCESS) {
                    throw IllegalStateException("GATT write could not start: $status")
                }
            } else {
                @Suppress("DEPRECATION")
                run {
                    rx.value = bytes
                    rx.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                    if (!gatt.writeCharacteristic(rx)) {
                        throw IllegalStateException("GATT write could not start")
                    }
                }
            }
            return
        }

        val server = gattServer
            ?: throw IllegalStateException("Start server or connect to a device first")

        val tx = server.getService(serviceUUID)?.getCharacteristic(txUUID)
            ?: throw IllegalStateException("Server TX characteristic unavailable")

        if (subscribers.isEmpty()) {
            throw IllegalStateException("No connected client subscribed to notifications")
        }

        subscribers.toList().forEach { address ->
            val device = connectedDevices[address] ?: return@forEach

            if (Build.VERSION.SDK_INT >= 33) {
                val status = server.notifyCharacteristicChanged(
                    device, tx, false, bytes
                )
                if (status != BluetoothStatusCodes.SUCCESS) {
                    emit("error", "Notification failed: $status")
                }
            } else {
                @Suppress("DEPRECATION")
                run {
                    tx.value = bytes
                    server.notifyCharacteristicChanged(device, tx, false)
                }
            }
        }
    }

    private fun disconnect() {
        clientGatt?.disconnect()
        clientGatt?.close()
        clientGatt = null
        emit("status", "Disconnected")
    }

    override fun onDestroy() {
        stopScan()
        stopServer()
        disconnect()
        super.onDestroy()
    }
}
