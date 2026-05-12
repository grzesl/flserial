package io.github.grzesl.flserial

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class FlserialPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    companion object {
        const val METHOD_CHANNEL        = "io.github.grzesl.flserial/usb"
        const val DATA_CHANNEL          = "io.github.grzesl.flserial/usb_data"
        const val USB_PERMISSION_ACTION = "io.github.grzesl.flserial.USB_PERMISSION"
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context

    private var eventSink: EventChannel.EventSink? = null
    private val connections = mutableMapOf<String, UsbConn>()
    private val mainHandler  = Handler(Looper.getMainLooper())
    private val writePool    = Executors.newSingleThreadExecutor()
    private var receiverRegistered = false

    private data class PendingOpen(val deviceName: String, val baud: Int, val result: MethodChannel.Result)
    private var pendingPermission: PendingOpen? = null

    private class UsbConn(
        val connection: UsbDeviceConnection,
        val iface:      UsbInterface,
        val bulkOut:    UsbEndpoint,
        val running:    AtomicBoolean,
        val thread:     Thread,
    )

    // ── Permission broadcast receiver ───────────────────────────────────────

    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action != USB_PERMISSION_ACTION) return
            val pending = pendingPermission ?: return
            pendingPermission = null
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            val usbManager = ctx.getSystemService(Context.USB_SERVICE) as UsbManager
            if (granted) {
                openDevice(usbManager, pending.deviceName, pending.baud, pending.result)
            } else {
                pending.result.error("PERMISSION_DENIED", "USB permission denied by user", null)
            }
        }
    }

    // ── FlutterPlugin ───────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, DATA_CHANNEL)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink) { eventSink = events }
            override fun onCancel(args: Any?) { eventSink = null }
        })
        registerReceiver()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        unregisterReceiver()
        connections.keys.toList().forEach { closeDevice(it) }
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(USB_PERMISSION_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(permissionReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun unregisterReceiver() {
        if (!receiverRegistered) return
        runCatching { context.unregisterReceiver(permissionReceiver) }
        receiverRegistered = false
    }

    // ── ActivityAware (needed for future activity-level operations) ─────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivity() {}

    // ── MethodChannel handler ───────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        when (call.method) {
            "listUsbSerialDevices" ->
                result.success(listSerialDevices(usbManager))

            "openUsbDevice" -> {
                val name = call.argument<String>("name")
                    ?: return result.error("INVALID_ARG", "name required", null)
                val baud = call.argument<Int>("baud") ?: 115200
                openDevice(usbManager, name, baud, result)
            }

            "closeUsbDevice" -> {
                val name = call.argument<String>("name")
                    ?: return result.error("INVALID_ARG", "name required", null)
                closeDevice(name)
                result.success(null)
            }

            "writeUsbDevice" -> {
                val name = call.argument<String>("name")
                    ?: return result.error("INVALID_ARG", "name required", null)
                val data = call.argument<ByteArray>("data")
                    ?: return result.error("INVALID_ARG", "data required", null)
                result.success(null)
                writePool.submit { writeDevice(name, data) }
            }

            else -> result.notImplemented()
        }
    }

    // ── Device discovery ────────────────────────────────────────────────────

    private fun isSerialDevice(device: UsbDevice): Boolean {
        if (device.deviceClass == UsbConstants.USB_CLASS_COMM) return true
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_COMM && iface.interfaceSubclass == 2)
                return true
            if (iface.interfaceClass == UsbConstants.USB_CLASS_VENDOR_SPEC && hasBulkEndpoints(iface))
                return true
        }
        // Known VIDs: FTDI, SiLabs CP210x, CH34x, STM32, Arduino, LeafLabs, mbed, Adafruit, Prolific
        return device.vendorId in setOf(0x0403, 0x10C4, 0x1A86, 0x0483, 0x2341, 0x1EAF, 0x0D28, 0x239A, 0x067B)
    }

    private fun hasBulkEndpoints(iface: UsbInterface): Boolean {
        var hasIn = false; var hasOut = false
        for (i in 0 until iface.endpointCount) {
            val ep = iface.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                if (ep.direction == UsbConstants.USB_DIR_IN) hasIn = true else hasOut = true
            }
        }
        return hasIn && hasOut
    }

    private fun listSerialDevices(usbManager: UsbManager): List<Map<String, Any>> =
        usbManager.deviceList.values
            .filter { isSerialDevice(it) }
            .map { d ->
                mapOf(
                    "name"         to d.deviceName,
                    "vid"          to d.vendorId,
                    "pid"          to d.productId,
                    "manufacturer" to (d.manufacturerName ?: ""),
                    "product"      to (d.productName      ?: "USB Serial"),
                )
            }

    private fun findDataInterface(device: UsbDevice): Triple<UsbInterface, UsbEndpoint, UsbEndpoint>? {
        for (cls in listOf(0x0A, UsbConstants.USB_CLASS_VENDOR_SPEC)) {
            for (i in 0 until device.interfaceCount) {
                val iface = device.getInterface(i)
                if (iface.interfaceClass != cls) continue
                var bulkIn:  UsbEndpoint? = null
                var bulkOut: UsbEndpoint? = null
                for (j in 0 until iface.endpointCount) {
                    val ep = iface.getEndpoint(j)
                    if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                        if (ep.direction == UsbConstants.USB_DIR_IN) bulkIn = ep
                        else bulkOut = ep
                    }
                }
                if (bulkIn != null && bulkOut != null)
                    return Triple(iface, bulkIn, bulkOut)
            }
        }
        return null
    }

    private fun findCommInterfaceId(device: UsbDevice): Int {
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_COMM) return iface.id
        }
        return 0
    }

    // ── Connection management ───────────────────────────────────────────────

    private fun openDevice(usbManager: UsbManager, deviceName: String, baud: Int, result: MethodChannel.Result) {
        val device = usbManager.deviceList[deviceName]
            ?: return result.error("NOT_FOUND", "Device not found: $deviceName", null)

        if (!usbManager.hasPermission(device)) {
            pendingPermission?.result?.error("PERMISSION_REPLACED", "Replaced by newer request", null)
            pendingPermission = PendingOpen(deviceName, baud, result)
            val pi = PendingIntent.getBroadcast(
                context, 0,
                Intent(USB_PERMISSION_ACTION),
                PendingIntent.FLAG_IMMUTABLE,
            )
            usbManager.requestPermission(device, pi)
            return
        }

        val conn = usbManager.openDevice(device)
            ?: return result.error("OPEN_FAILED", "Cannot open USB device", null)

        val triple = findDataInterface(device)
        if (triple == null) {
            conn.close()
            return result.error("NO_INTERFACE", "No bulk serial interface found", null)
        }
        val (iface, bulkIn, bulkOut) = triple

        if (!conn.claimInterface(iface, true)) {
            conn.close()
            return result.error("CLAIM_FAILED", "Cannot claim USB interface", null)
        }

        when {
            device.vendorId == 0x067B                              -> initPl2303(conn, device, baud)
            iface.interfaceClass == 0x0A                           -> initCdcAcm(conn, device, baud)
            iface.interfaceClass == UsbConstants.USB_CLASS_VENDOR_SPEC -> initVendorDevice(conn, device, iface, baud)
        }

        val ftdiOffset = if (device.vendorId == 0x0403) 2 else 0
        val running    = AtomicBoolean(true)
        val buf        = ByteArray(bulkIn.maxPacketSize.coerceAtLeast(64))
        val thread     = Thread {
            while (running.get()) {
                val len = conn.bulkTransfer(bulkIn, buf, buf.size, 100)
                if (len > ftdiOffset) {
                    val data = buf.copyOfRange(ftdiOffset, len)
                    mainHandler.post {
                        eventSink?.success(mapOf("name" to deviceName, "data" to data))
                    }
                }
            }
        }.also { it.isDaemon = true; it.start() }

        connections[deviceName] = UsbConn(conn, iface, bulkOut, running, thread)
        result.success(true)
    }

    private fun closeDevice(deviceName: String) {
        val c = connections.remove(deviceName) ?: return
        c.running.set(false)
        runCatching { c.thread.join(500) }
        c.connection.releaseInterface(c.iface)
        c.connection.close()
    }

    private fun writeDevice(deviceName: String, data: ByteArray) {
        val c = connections[deviceName] ?: return
        c.connection.bulkTransfer(c.bulkOut, data, data.size, 2000)
    }

    // ── CDC ACM ─────────────────────────────────────────────────────────────

    private fun initCdcAcm(conn: UsbDeviceConnection, device: UsbDevice, baud: Int) {
        val wIndex = findCommInterfaceId(device)
        val coding = ByteArray(7)
        coding[0] = (baud        and 0xFF).toByte()
        coding[1] = (baud shr  8 and 0xFF).toByte()
        coding[2] = (baud shr 16 and 0xFF).toByte()
        coding[3] = (baud shr 24 and 0xFF).toByte()
        coding[4] = 0; coding[5] = 0; coding[6] = 8   // 1 stop, no parity, 8 data
        conn.controlTransfer(0x21, 0x20, 0, wIndex, coding, 7, 2000)
        conn.controlTransfer(0x21, 0x22, 0x03, wIndex, null, 0, 2000)
    }

    // ── PL2303 (Prolific) ────────────────────────────────────────────────────

    private fun initPl2303(conn: UsbDeviceConnection, device: UsbDevice, baud: Int) {
        val isHxn = device.productId in setOf(
            0x23A3, 0x23A4, 0x23A5, 0x23A6,
            0x3414, 0x3415, 0x3416, 0x3417,
            0x0609, 0x3410,
        )
        if (isHxn) initPl2303Hxn(conn, baud) else initPl2303Hx(conn, baud)
    }

    private fun initPl2303Hx(conn: UsbDeviceConnection, baud: Int) {
        val buf = ByteArray(1)
        conn.controlTransfer(0xC0, 0x01, 0, 0, buf, 1, 200)
        conn.controlTransfer(0x40, 0x01, 0x0404, 0, null, 0, 200)
        conn.controlTransfer(0xC0, 0x01, 0, 0, buf, 1, 200)
        conn.controlTransfer(0xC0, 0x01, 0, 0, buf, 1, 200)
        conn.controlTransfer(0x40, 0x01, 0x0404, 1, null, 0, 200)
        conn.controlTransfer(0xC0, 0x04, 0x02, 0, buf, 1, 200)
        conn.controlTransfer(0x40, 0x04, 0x08, 0, null, 0, 200)
        conn.controlTransfer(0x40, 0x04, 0x00, 0, null, 0, 200)
        pl2303SetLineCoding(conn, baud)
        conn.controlTransfer(0x21, 0x22, 0x03, 0, null, 0, 200)
        conn.controlTransfer(0x40, 0x01, 0x0505, 0x1311, null, 0, 200)
    }

    private fun initPl2303Hxn(conn: UsbDeviceConnection, baud: Int) {
        conn.controlTransfer(0x40, 0x01, 0x08, 0, null, 0, 200)
        conn.controlTransfer(0x40, 0x01, 0x09, 0, null, 0, 200)
        conn.controlTransfer(0x40, 0x01, 0x0d, 0, null, 0, 200)
        pl2303SetLineCoding(conn, baud)
        conn.controlTransfer(0x21, 0x22, 0x03, 0, null, 0, 200)
    }

    private fun pl2303SetLineCoding(conn: UsbDeviceConnection, baud: Int) {
        val coding = ByteArray(7)
        coding[0] = (baud        and 0xFF).toByte()
        coding[1] = (baud shr  8 and 0xFF).toByte()
        coding[2] = (baud shr 16 and 0xFF).toByte()
        coding[3] = (baud shr 24 and 0xFF).toByte()
        coding[4] = 0; coding[5] = 0; coding[6] = 8
        conn.controlTransfer(0x21, 0x20, 0, 0, coding, 7, 200)
    }

    // ── Vendor-specific ──────────────────────────────────────────────────────

    private fun initVendorDevice(conn: UsbDeviceConnection, device: UsbDevice, iface: UsbInterface, baud: Int) {
        when (device.vendorId) {
            0x0403 -> initFtdi(conn, baud)
            0x1A86 -> initCh340(conn, baud)
            0x10C4 -> initCp210x(conn, iface, baud)
        }
    }

    private fun initFtdi(conn: UsbDeviceConnection, baud: Int) {
        conn.controlTransfer(0x40, 0x00, 0, 0, null, 0, 200)
        conn.controlTransfer(0x40, 0x00, 1, 0, null, 0, 200)
        conn.controlTransfer(0x40, 0x00, 2, 0, null, 0, 200)
        conn.controlTransfer(0x40, 0x09, 16, 0, null, 0, 200)
        val (wVal, wIdx) = ftdiBaudArgs(baud)
        conn.controlTransfer(0x40, 0x03, wVal, wIdx, null, 0, 200)
        conn.controlTransfer(0x40, 0x04, 8, 0, null, 0, 200)
        conn.controlTransfer(0x40, 0x02, 0, 0, null, 0, 200)
        conn.controlTransfer(0x40, 0x01, 0x0303, 0, null, 0, 200)
    }

    private fun ftdiBaudArgs(baud: Int): Pair<Int, Int> {
        val fracCode = intArrayOf(0, 3, 2, 4, 1, 5, 6, 7)
        val nExact   = 3_000_000.0 / baud
        val n        = nExact.toLong().coerceIn(2, 16383)
        val sub      = ((nExact - n) * 8 + 0.5).toInt().coerceIn(0, 7)
        val encoded  = n.toInt() or (fracCode[sub] shl 14)
        return Pair(encoded and 0xFFFF, (encoded shr 16) and 0xFF)
    }

    private fun initCh340(conn: UsbDeviceConnection, baud: Int) {
        conn.controlTransfer(0x40, 0xA1, 0, 0, null, 0, 200)
        val (v, idx) = ch340BaudArgs(baud)
        conn.controlTransfer(0x40, 0x9A, v, idx, null, 0, 200)
        conn.controlTransfer(0x40, 0xA4, 0xBF, 0, null, 0, 200)
        conn.controlTransfer(0x40, 0xA4, 0x9F, 0, null, 0, 200)
    }

    private fun ch340BaudArgs(baud: Int): Pair<Int, Int> = when (baud) {
        2400   -> Pair(0xD901, 0x0038)
        4800   -> Pair(0x6402, 0x001F)
        9600   -> Pair(0xB202, 0x0013)
        19200  -> Pair(0xD902, 0x000D)
        38400  -> Pair(0x6403, 0x000A)
        57600  -> Pair(0xD203, 0x000F)
        115200 -> Pair(0xCC03, 0x0008)
        230400 -> Pair(0xD304, 0x0004)
        460800 -> Pair(0xE604, 0x0002)
        921600 -> Pair(0xF304, 0x0001)
        else   -> Pair(0xCC03, 0x0008)
    }

    private fun initCp210x(conn: UsbDeviceConnection, iface: UsbInterface, baud: Int) {
        val ifIdx = iface.id
        conn.controlTransfer(0x41, 0x00, 0x0001, ifIdx, null, 0, 200)
        val baudBytes = ByteArray(4).also { b ->
            b[0] = (baud        and 0xFF).toByte()
            b[1] = (baud shr  8 and 0xFF).toByte()
            b[2] = (baud shr 16 and 0xFF).toByte()
            b[3] = (baud shr 24 and 0xFF).toByte()
        }
        conn.controlTransfer(0x40, 0x1E, 0, ifIdx, baudBytes, 4, 200)
        conn.controlTransfer(0x41, 0x03, 0x0800, ifIdx, null, 0, 200)
        conn.controlTransfer(0x41, 0x07, 0x0303, ifIdx, null, 0, 200)
    }
}
