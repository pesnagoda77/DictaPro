package com.dictapro.app

import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import com.google.android.play.core.assetpacks.AssetPackLocation
import com.google.android.play.core.assetpacks.AssetPackManager
import com.google.android.play.core.assetpacks.AssetPackManagerFactory
import com.google.android.play.core.assetpacks.model.AssetPackStatus
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.BufferedInputStream
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val CHANNEL = "dictapro/convert"
    private val MODEL_CHANNEL = "dictapro/model"
    private val KEEPALIVE_CHANNEL = "dictapro/keepalive"
    private val RECORDINGS_CHANNEL = "dictapro/recordings"
    private val TAG = "DictaPro"
    private val PACK_NAME = "gigaam_pack"
    /// Task 116 П.2: публичная папка записей (видна пользователю в Files).
    private val RECORDINGS_RELATIVE_PATH =
        "${android.os.Environment.DIRECTORY_DOCUMENTS}/DictaPro/Записи"

    // Task 116 (Славан): файл, открытый «в DictaPro» из проводника.
    private var pendingOpenUri: String? = null
    private var pendingOpenName: String? = null

    private fun stashViewIntent(intent: android.content.Intent?) {
        if (intent?.action != android.content.Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        pendingOpenUri = uri.toString()
        var name: String? = null
        try {
            contentResolver.query(
                uri,
                arrayOf(android.provider.OpenableColumns.DISPLAY_NAME),
                null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) name = c.getString(idx)
                }
            }
        } catch (_: Exception) {}
        pendingOpenName = name ?: uri.lastPathSegment ?: "audio"
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        stashViewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        stashViewIntent(intent)
        super.configureFlutterEngine(flutterEngine)

        // Task 116 П.2: публикация/чтение/удаление записей в публичной
        // Documents/DictaPro/Записи. На API 29+ — через MediaStore
        // (scoped storage, разрешения не нужны для своих файлов);
        // ≤28 — прямой путь + медиасканер.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDINGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingOpenFile" -> {
                    // Отдать Dart файл, открытый снаружи (и забыть его).
                    val uri = pendingOpenUri
                    pendingOpenUri = null
                    val name = pendingOpenName
                    pendingOpenName = null
                    if (uri == null) {
                        result.success(null)
                    } else {
                        result.success(mapOf("uri" to uri, "name" to (name ?: "")))
                    }
                }
                "ensureRecordingsFolder" -> {
                    // Славан 24.10: папка должна существовать и быть видна
                    // сразу после установки, а не после первой записи.
                    Thread {
                        try {
                            val ok = ensureRecordingsFolderNative()
                            runOnUiThread { result.success(ok) }
                        } catch (e: Exception) {
                            Log.e(TAG, "ensureRecordingsFolder FAILED", e)
                            runOnUiThread { result.success(false) }
                        }
                    }.start()
                }
                "publishRecording" -> {
                    val srcPath = call.argument<String>("srcPath") ?: ""
                    val displayName = call.argument<String>("displayName") ?: ""
                    if (srcPath.isEmpty() || displayName.isEmpty()) {
                        result.error("INVALID_ARGUMENTS", "srcPath/displayName", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val out = publishRecordingToDocuments(srcPath, displayName)
                            runOnUiThread { result.success(out) }
                        } catch (e: Exception) {
                            Log.e(TAG, "publishRecording FAILED", e)
                            runOnUiThread { result.success(null) }
                        }
                    }.start()
                }
                "materializeRecording" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    val name = call.argument<String>("name") ?: "recording.wav"
                    if (uri.isEmpty()) {
                        result.error("INVALID_ARGUMENTS", "uri", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val path = materializeRecording(uri, name)
                            runOnUiThread { result.success(path) }
                        } catch (e: Exception) {
                            Log.e(TAG, "materializeRecording FAILED", e)
                            runOnUiThread { result.success(null) }
                        }
                    }.start()
                }
                "deleteRecording" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    try {
                        if (uri.isNotEmpty()) {
                            contentResolver.delete(Uri.parse(uri), null, null)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "deleteRecording: ${e.message}")
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Task 038: фактическое состояние исключения из экономии батареи и
        // прямой выход на экран батареи приложения. MIUI-запрос из
        // flutter_foreground_task открывает системный выбор, после которого
        // непонятно, включилось ли — здесь проверяем реальный флаг.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KEEPALIVE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "batteryUnrestrictedStatus" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            result.success(if (pm.isIgnoringBatteryOptimizations(packageName)) 1 else 0)
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }
                "openBatterySettings" -> {
                    try {
                        val i = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            Intent("android.settings.APP_BATTERY_SETTINGS").apply {
                                data = Uri.parse("package:$packageName")
                            }
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        } else {
                            Intent(Settings.ACTION_SETTINGS)
                        }
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            })
                            result.success(true)
                        } catch (e2: Exception) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openFolder" -> {
                    // Task 116 фидбек: старый URI (resource/folder + ручной
                    // percent-encoding) не открывался почти нигде — кириллица
                    // в пути («Записи») не кодировалась. Правильно — строить
                    // URI через DocumentsContract: системный Files (DocumentsUI)
                    // открывает папку напрямую.
                    val path = call.argument<String>("path") ?: ""
                    try {
                        val dir = java.io.File(path)
                        if (!dir.exists()) dir.mkdirs()
                        val rel = path.removePrefix("/storage/emulated/0/")
                        var opened = false
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                            try {
                                val docUri = android.provider.DocumentsContract.buildDocumentUri(
                                    "com.android.externalstorage.documents",
                                    "primary:$rel"
                                )
                                val intent = android.content.Intent(android.content.Intent.ACTION_VIEW)
                                intent.setDataAndType(
                                    docUri,
                                    android.provider.DocumentsContract.Document.MIME_TYPE_DIR
                                )
                                intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                opened = true
                            } catch (e: Exception) {
                                Log.e(TAG, "openFolder documentsui failed", e)
                            }
                        }
                        if (!opened) {
                            // Фолбэк: выбор «проводника» у пользователя.
                            try {
                                val intent = android.content.Intent(android.content.Intent.ACTION_VIEW)
                                intent.setDataAndType(
                                    android.net.Uri.parse("content://com.android.externalstorage.documents/document/primary:" + rel),
                                    "vnd.android.document/directory"
                                )
                                intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                opened = true
                            } catch (e: Exception) {
                                Log.e(TAG, "openFolder fallback failed", e)
                            }
                        }
                        runOnUiThread { result.success(opened) }
                    } catch (e: Exception) {
                        Log.e(TAG, "openFolder failed", e)
                        runOnUiThread { result.success(false) }
                    }
                }
                "extractFragmentWav" -> {
                    val path = call.argument<String>("path")
                    val fromMs = (call.argument<Int>("fromMs")) ?: 0
                    val toMs = (call.argument<Int>("toMs")) ?: 0
                    if (path == null) {
                        result.error("INVALID_ARGUMENTS", "path is null", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val tmp = File(cacheDir, "fragment_tmp.wav")
                            extractRangeToWav(path, tmp.absolutePath, fromMs.toLong(), toMs.toLong())
                            runOnUiThread { result.success(tmp.absolutePath) }
                        } catch (e: Exception) {
                            Log.e(TAG, "extractFragmentWav FAILED", e)
                            runOnUiThread { result.error("EXTRACT_FAILED", e.message, null) }
                        }
                    }.start()
                }
                "convertToWav" -> {
                    val inputPath = call.argument<String>("inputPath")
                    val outputPath = call.argument<String>("outputPath")
                    if (inputPath == null || outputPath == null) {
                        result.error("INVALID_ARGUMENTS", "inputPath or outputPath is null", null)
                        return@setMethodCallHandler
                    }
                    // Декодирование длинного аудио (mp3/стерео/44,1 кГц) занимает минуты:
                    // выносим из главного потока, иначе Android показывает «приложение не отвечает».
                    Thread {
                        try {
                            Log.d(TAG, "Starting conversion: input=$inputPath")
                            convertAudioToWav(inputPath, outputPath, 16000, 1)
                            Log.d(TAG, "Conversion OK")
                            runOnUiThread { result.success(mapOf("success" to true)) }
                        } catch (e: Exception) {
                            Log.e(TAG, "Conversion FAILED", e)
                            runOnUiThread { result.success(mapOf("success" to false, "error" to e.message)) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        // Прослойка к install-time asset pack с моделью GigaAM (task 019).
        // Возвращает путь к файлам пакета; null — пак недоступен
        // (APK-раздача: модель тогда копируется из flutter-ассетов на Dart-стороне).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MODEL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGigaamModelPath" -> {
                    try {
                        val pm: AssetPackManager = AssetPackManagerFactory.getInstance(this)
                        val loc: AssetPackLocation? = pm.getPackLocation(PACK_NAME)
                        val path = loc?.assetsPath() // null, если пак недоступен/не установлен
                        Log.d(TAG, "asset pack location: $path (status may vary)")
                        result.success(path)
                    } catch (e: Exception) {
                        Log.w(TAG, "asset pack unavailable: ${e.message}")
                        result.success(null)
                    }
                }
                // Task 067: fast-follow — пакет догружается Play ПОСЛЕ установки.
                // Отдаём статус доставки и прогресс, чтобы UI показывал
                // «модель загружается» и не падал на первом запуске.
                // Task 067: fast-follow — пакет догружается Play ПОСЛЕ установки.
                // Отдаём два факта: доступен ли пакет на диске и ставилось ли
                // приложение из Play (для APK-раздачи пакета не будет вовсе).
                "getGigaamPackState" -> {
                    try {
                        val pm: AssetPackManager = AssetPackManagerFactory.getInstance(this)
                        val loc: AssetPackLocation? = pm.getPackLocation(PACK_NAME)
                        val available = loc?.assetsPath() != null
                        val installer = if (Build.VERSION.SDK_INT >= 30) {
                            packageManager.getInstallSourceInfo(packageName).installingPackageName
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getInstallerPackageName(packageName)
                        }
                        val m = hashMapOf<String, Any>(
                            "available" to available,
                            "fromPlay" to (installer == "com.android.vending")
                        )
                        result.success(m)
                    } catch (e: Exception) {
                        Log.w(TAG, "pack state unavailable: ${e.message}")
                        result.success(null)
                    }
                }
                "requestGigaamPack" -> {
                    try {
                        val pm: AssetPackManager = AssetPackManagerFactory.getInstance(this)
                        pm.fetch(listOf(PACK_NAME))
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "pack fetch failed: ${e.message}")
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Task 116 П.2: запись → публичная Documents/DictaPro/Записи.
    // Возвращает map("path" — абсолютный путь для показа в UI,
    // "uri" — content:// для чтения/удаления через MediaStore;
    // на ≤API 28 uri отсутствует, читаем напрямую по path).
    /// Task 116 (Славан): создать Documents/DictaPro/Записи сразу.
    /// MediaStore не умеет «пустую папку» — кладём крошечный файл-подсказку,
    /// только если в папке ещё ничего нет (без дублей при перезапусках).
    private fun ensureRecordingsFolderNative(): Boolean {
        return if (Build.VERSION.SDK_INT >= 29) {
            val collection = android.provider.MediaStore.Files.getContentUri(
                android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val relArg = RECORDINGS_RELATIVE_PATH + "/"
            val hasFiles = contentResolver.query(
                collection,
                arrayOf(android.provider.MediaStore.Files.FileColumns._ID),
                android.provider.MediaStore.Files.FileColumns.RELATIVE_PATH + "=?",
                arrayOf(relArg),
                null
            )?.use { it.count > 0 } ?: false
            if (hasFiles) return true
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Files.FileColumns.DISPLAY_NAME,
                    "Здесь появляются записи DictaPro.txt")
                put(android.provider.MediaStore.Files.FileColumns.MIME_TYPE, "text/plain")
                put(android.provider.MediaStore.Files.FileColumns.RELATIVE_PATH,
                    RECORDINGS_RELATIVE_PATH)
            }
            val uri = contentResolver.insert(collection, values) ?: return false
            contentResolver.openOutputStream(uri, "w")?.use { os ->
                os.write("Аудиозаписи приложения DictaPro сохраняются в эту папку."
                    .toByteArray())
            }
            true
        } else {
            val dir = java.io.File(
                android.os.Environment.getExternalStoragePublicDirectory(
                    android.os.Environment.DIRECTORY_DOCUMENTS),
                "DictaPro/Записи")
            if (!dir.exists()) dir.mkdirs()
            val marker = java.io.File(dir, "Здесь появляются записи DictaPro.txt")
            if (!marker.exists()) {
                marker.writeText("Аудиозаписи приложения DictaPro сохраняются в эту папку.")
                android.media.MediaScannerConnection.scanFile(
                    this, arrayOf(marker.absolutePath), arrayOf("text/plain"), null)
            }
            dir.exists()
        }
    }

    private fun publishRecordingToDocuments(srcPath: String, displayName: String): Map<String, String>? {
        val src = File(srcPath)
        if (!src.exists() || !src.canRead()) throw Exception("src missing: $srcPath")

        if (Build.VERSION.SDK_INT >= 29) {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Files.FileColumns.DISPLAY_NAME, displayName)
                put(android.provider.MediaStore.Files.FileColumns.MIME_TYPE, mimeForName(displayName))
                put(android.provider.MediaStore.Files.FileColumns.RELATIVE_PATH, RECORDINGS_RELATIVE_PATH)
            }
            val collection = android.provider.MediaStore.Files.getContentUri(
                android.provider.MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = contentResolver.insert(collection, values)
                ?: throw Exception("MediaStore insert failed")
            var failed = false
            try {
                contentResolver.openOutputStream(uri, "w")?.use { os ->
                    java.io.BufferedInputStream(java.io.FileInputStream(src)).use { input ->
                        val buf = ByteArray(1 shl 20)
                        while (true) {
                            val n = input.read(buf)
                            if (n <= 0) break
                            os.write(buf, 0, n)
                        }
                    }
                } ?: throw Exception("openOutputStream failed")
            } catch (e: Exception) {
                failed = true
                try { contentResolver.delete(uri, null, null) } catch (_: Exception) {}
                throw e
            }
            // Фактическое имя (MediaStore мог добавить суффикс при коллизии).
            val realName = queryDisplayName(uri) ?: displayName
            return mapOf(
                "path" to "/storage/emulated/0/$RECORDINGS_RELATIVE_PATH/$realName",
                "uri" to uri.toString(),
            )
        }

        // ≤API 28: прямой путь, разрешение WRITE_EXTERNAL_STORAGE уже есть.
        val dir = java.io.File(
            android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_DOCUMENTS),
            "DictaPro/Записи")
        if (!dir.exists()) dir.mkdirs()
        var dst = java.io.File(dir, displayName)
        var stem = displayName.substringBeforeLast('.')
        val ext = displayName.substringAfterLast('.', "")
        var i = 1
        while (dst.exists()) {
            dst = java.io.File(dir, "$stem($i)${if (ext.isEmpty()) "" else ".$ext"}")
            i++
        }
        java.io.BufferedInputStream(java.io.FileInputStream(src)).use { input ->
            java.io.FileOutputStream(dst).use { os ->
                val buf = ByteArray(1 shl 20)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    os.write(buf, 0, n)
                }
            }
        }
        // Показать файл-менеджерам (MediaScanner).
        try {
            android.media.MediaScannerConnection.scanFile(
                this, arrayOf(dst.absolutePath), null, null)
        } catch (_: Exception) {}
        return mapOf("path" to dst.absolutePath)
    }

    // Task 116 П.2: content:// → временный файл в app-кэше для плеера,
    // конвертера, шаринга. Scoped storage запрещает читать Documents
    // напрямую по пути — но создатель читает через ContentResolver.
    private fun materializeRecording(uriString: String, name: String): String {
        val uri = Uri.parse(uriString)
        val safe = name.replace(Regex("[^\\w.\\- ()]"), "_")
        val dir = java.io.File(cacheDir, "materialized")
        if (!dir.exists()) dir.mkdirs()
        var dst = java.io.File(dir, safe)
        var stem = safe.substringBeforeLast('.')
        val ext = safe.substringAfterLast('.', "")
        var i = 1
        while (dst.exists()) {
            dst = java.io.File(dir, "$stem(${i})${if (ext.isEmpty()) "" else ".$ext"}")
            i++
        }
        contentResolver.openInputStream(uri)?.use { input ->
            java.io.FileOutputStream(dst).use { os ->
                val buf = ByteArray(1 shl 20)
                while (true) {
                    val n = input.read(buf)
                    if (n <= 0) break
                    os.write(buf, 0, n)
                }
            }
        } ?: throw Exception("openInputStream failed: $uriString")
        return dst.absolutePath
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri,
                arrayOf(android.provider.MediaStore.Files.FileColumns.DISPLAY_NAME),
                null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) else null
            }
        } catch (_: Exception) { null }
    }

    private fun mimeForName(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "wav" -> "audio/wav"
            "m4a" -> "audio/mp4"
            "aac" -> "audio/aac"
            else -> "application/octet-stream"
        }
    }

    // 21.10: вырезка диапазона [fromMs; toMs) в отдельный WAV через
    // MediaExtractor+MediaCodec (декодирование в PCM, без перекодирования
    // формата контейнера — файл гарантированно валидный WAV).
    private fun extractRangeToWav(inputPath: String, outputPath: String, fromMs: Long, toMs: Long) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(inputPath)
            var trackIndex = -1
            var mime = ""
            var sampleRate = 16000
            var channels = 1
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val m = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (m.startsWith("audio/")) {
                    trackIndex = i
                    mime = m
                    sampleRate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    break
                }
            }
            if (trackIndex < 0) throw Exception("no audio track")
            extractor.selectTrack(trackIndex)

            val codec = MediaCodec.createDecoderByType(mime)
            val fmt = extractor.getTrackFormat(trackIndex)
            codec.configure(fmt, null, null, 0)
            codec.start()

            val fromUs = fromMs * 1000L
            val toUs = toMs * 1000L
            extractor.seekTo(fromUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

            val pcm = File(outputPath + ".pcm")
            val outStream = java.io.FileOutputStream(pcm)
            var pcmBytes = 0L
            var sawInputEos = false
            var sawOutputEos = false
            val info = MediaCodec.BufferInfo()
            var guard = 0
            while (!sawOutputEos && guard < 100000) {
                guard++
                if (!sawInputEos) {
                    val inIdx = codec.dequeueInputBuffer(10000)
                    if (inIdx >= 0) {
                        val ib = codec.getInputBuffer(inIdx)!!
                        val sz = extractor.readSampleData(ib, 0)
                        if (sz < 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            sawInputEos = true
                        } else {
                            val pts = extractor.sampleTime
                            if (pts > toUs) {
                                codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                sawInputEos = true
                            } else {
                                codec.queueInputBuffer(inIdx, 0, sz, pts, 0)
                            }
                            extractor.advance()
                        }
                    }
                }
                val outIdx = codec.dequeueOutputBuffer(info, 10000)
                if (outIdx >= 0) {
                    val ob = codec.getOutputBuffer(outIdx)!!
                    // Пишем только сэмплы, попавшие в диапазон времени.
                    val ptsUs = info.presentationTimeUs
                    val bytesPerSample = 2 // 16-бит PCM после декодера
                    val samplesTotal = info.size / (2 * channels)
                    val secPerSample = 1_000_000.0 / (sampleRate * channels)
                    var writeFrom = 0
                    var writeUntil = samplesTotal
                    if (ptsUs < fromUs) {
                        val skip = ((fromUs - ptsUs) / secPerSample).toLong()
                        writeFrom = skip.toInt()
                    }
                    if (ptsUs + samplesTotal.toLong() * secPerSample.toLong() > toUs) {
                        val keep = ((toUs - ptsUs) / secPerSample).toLong().toInt()
                        if (keep in 0 until writeUntil) writeUntil = keep
                    }
                    if (writeUntil > writeFrom) {
                        ob.position(writeFrom * 2 * channels)
                        val bytesToWrite = (writeUntil - writeFrom) * 2 * channels
                        val arr = ByteArray(bytesToWrite)
                        ob.get(arr)
                        outStream.write(arr)
                        pcmBytes += bytesToWrite
                    }
                    codec.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) sawOutputEos = true
                } else if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (sawInputEos) { /* ждём хвост декода */ }
                }
            }
            codec.stop()
            codec.release()
            extractor.release()
            outStream.flush()
            outStream.close()
            if (pcmBytes <= 0L) throw Exception("empty extract")

            // WAV-заголовок поверх PCM.
            val out = File(outputPath)
            val wav = java.io.RandomAccessFile(out, "rw")
            val hdr = ByteArray(44)
            fun put32(off: Int, v: Int) { wav.seek(off.toLong()); wav.writeInt(Integer.reverseBytes(v)) }
            fun put16(off: Int, v: Int) { wav.seek(off.toLong()); wav.writeShort(Integer.reverseBytes(v).toInt() shr 16) }
            wav.seek(0); wav.write(byteArrayOf(0x52,0x49,0x46,0x46)) // RIFF
            put32(4, 36 + pcmBytes.toInt())
            wav.seek(8); wav.write(byteArrayOf(0x57,0x41,0x56,0x45)) // WAVE
            wav.seek(12); wav.write(byteArrayOf(0x66,0x6D,0x74,0x20)) // fmt
            put32(16, 16)
            put16(20, 1) // PCM
            put16(22, channels)
            put32(24, sampleRate)
            put32(28, sampleRate * channels * 2)
            put16(32, channels * 2)
            put16(34, 16)
            wav.seek(36); wav.write(byteArrayOf(0x64,0x61,0x74,0x61)) // data
            put32(40, pcmBytes.toInt())
            // приклеиваем PCM
            wav.seek(44)
            java.io.FileInputStream(pcm).use { fis ->
                val buf = ByteArray(1 shl 20)
                while (true) {
                    val n = fis.read(buf)
                    if (n <= 0) break
                    wav.write(buf, 0, n)
                }
            }
            wav.close()
            pcm.delete()
        } finally {
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    private fun convertAudioToWav(inputPath: String, outputPath: String, targetSampleRate: Int, targetChannels: Int) {
        Log.d(TAG, "Starting conversion: input=$inputPath, output=$outputPath")
        
        // Validate input file exists and is readable
        val inputFile = File(inputPath)
        if (!inputFile.exists() || !inputFile.canRead()) {
            throw Exception("Input file does not exist or is not readable: $inputPath")
        }
        if (inputFile.length() < 1024) {
            throw Exception("Input file too small (less than 1KB), likely corrupted")
        }
        
        val extractor = MediaExtractor()
        
        // Setup data source with error handling
        try {
            if (inputPath.startsWith("content://")) {
                val uri = Uri.parse(inputPath)
                contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                    Log.d(TAG, "Content URI opened: offset=${afd.startOffset}, len=${afd.length}")
                    extractor.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                } ?: throw Exception("Cannot open content URI: $inputPath")
            } else {
                Log.d(TAG, "Direct file path: $inputPath")
                extractor.setDataSource(inputPath)
            }
        } catch (e: Exception) {
            extractor.release()
            Log.e(TAG, "MediaExtractor failed to open", e)
            throw Exception("Cannot open audio file: ${e.message}")
        }

        var audioTrackIndex = -1
        var inputSampleRate = 44100
        var inputChannels = 2
        var mimeType = "unknown"
        var format: MediaFormat? = null
        var sourceDurationUs = 0L

        Log.d(TAG, "Track count: ${extractor.trackCount}")
        for (i in 0 until extractor.trackCount) {
            val trackFormat = extractor.getTrackFormat(i)
            val mime = trackFormat.getString(MediaFormat.KEY_MIME) ?: ""
            Log.d(TAG, "Track $i: mime=$mime")
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                inputSampleRate = try { trackFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE) } catch (_: Exception) { 44100 }
                inputChannels = try { trackFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT) } catch (_: Exception) { 2 }
                mimeType = mime
                format = trackFormat
                sourceDurationUs = try { trackFormat.getLong(MediaFormat.KEY_DURATION) } catch (_: Exception) { 0L }
                Log.d(TAG, "Selected audio track $i: $inputSampleRate Hz, $inputChannels ch, mime=$mime")
                break
            }
        }

        if (audioTrackIndex == -1) {
            extractor.release()
            Log.e(TAG, "No audio track found in file")
            throw Exception("No audio track found — file may be corrupted or unsupported format")
        }

        extractor.selectTrack(audioTrackIndex)

        // Create decoder
        val codec: MediaCodec = try {
            MediaCodec.createDecoderByType(mimeType)
        } catch (e: Exception) {
            extractor.release()
            Log.e(TAG, "Failed to create decoder for $mimeType", e)
            throw Exception("Cannot decode this audio format ($mimeType): ${e.message}")
        }

        // Configure and start
        try {
            codec.configure(format, null, null, 0)
            codec.start()
        } catch (e: Exception) {
            codec.release()
            extractor.release()
            Log.e(TAG, "Codec configure/start failed", e)
            throw Exception("Codec initialization failed: ${e.message}")
        }

        val bufferInfo = MediaCodec.BufferInfo()
        val tempPcmFile = File("${outputPath}.tmp.pcm")
        val pcmFos = FileOutputStream(tempPcmFile)
        var isEOS = false
        var hasOutput = false

        try {
            // Важно: раньше на каждой итерации стояли таймауты по 10 мс — на длинном файле
            // это десятки тысяч холостых ожиданий (mp3 на 25 минут декодировался >10 минут).
            // Теперь забираем всё, что готово, без ожидания, и уступаем поток только когда пусто.
            var eosQueued = false
        var emptyRounds = 0
            while (!isEOS) {
                var fed = false
                while (true) {
                    val inputBufferId = codec.dequeueInputBuffer(0)
                    if (inputBufferId < 0) break
                    val inputBuffer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        codec.getInputBuffer(inputBufferId)!!
                    } else {
                        @Suppress("DEPRECATION")
                        codec.inputBuffers[inputBufferId]
                    }
                    val sampleSize = extractor.readSampleData(inputBuffer, 0)
                    if (sampleSize < 0) {
                        codec.queueInputBuffer(inputBufferId, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        eosQueued = true
                        fed = true
                        break
                    } else {
                        codec.queueInputBuffer(inputBufferId, 0, sampleSize, extractor.sampleTime, 0)
                        extractor.advance()
                        fed = true
                    }
                }

                var gotOutput = false
                var outputBufferId = codec.dequeueOutputBuffer(bufferInfo, 0)
                while (outputBufferId >= 0) {
                    gotOutput = true
                    hasOutput = true
                    val outputBuffer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        codec.getOutputBuffer(outputBufferId)!!
                    } else {
                        @Suppress("DEPRECATION")
                        codec.outputBuffers[outputBufferId]
                    }
                    val chunk = ByteArray(bufferInfo.size)
                    outputBuffer.position(bufferInfo.offset)
                    outputBuffer.get(chunk)
                    pcmFos.write(chunk)
                    codec.releaseOutputBuffer(outputBufferId, false)
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        isEOS = true
                    }
                    outputBufferId = codec.dequeueOutputBuffer(bufferInfo, 0)
                }
                // Ждём именно флаг конца потока из декодера: иначе можно потерять хвост файла.
                if (eosQueued && !gotOutput && !fed) {
                    emptyRounds++
                    if (emptyRounds > 3000) { // ~3 с без ответа — аварийный выход
                        Log.w(TAG, "decoder stalled; forcing EOS")
                        isEOS = true
                    }
                } else {
                    emptyRounds = 0
                }
                if (!fed && !gotOutput) {
                    // ничего не готово — короткая уступка, чтобы не жечь процессор впустую
                    Thread.sleep(1)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Decode loop error", e)
            throw Exception("Decoding failed: ${e.message}")
        } finally {
            try { pcmFos.close() } catch (_: Exception) {}
            try { codec.stop() } catch (_: Exception) {}
            try { codec.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }

        if (!hasOutput) {
            tempPcmFile.delete()
            throw Exception("No audio data decoded — file may be corrupted or in unsupported format")
        }

        // Потоковая обработка блоками: раньше весь PCM читался в память одним массивом
        // (для mp3 25 минут это ~272 МБ) — на телефоне это OutOfMemoryError.
        val tmpSize = tempPcmFile.length()
        if (tmpSize <= 0) {
            tempPcmFile.delete()
            throw Exception("Decoded audio is empty")
        }
        Log.d(TAG, "Decoded PCM: ${tmpSize} bytes; streaming to WAV")
        streamToWav16k(tempPcmFile, outputPath, inputSampleRate, inputChannels, targetSampleRate, targetChannels)
        tempPcmFile.delete()
        try {
            val wavBytes = File(outputPath).length() - 44
            val wavSec = wavBytes / (targetSampleRate.toDouble() * targetChannels * 2)
            val srcSec = if (sourceDurationUs > 0) sourceDurationUs / 1_000_000.0 else -1.0
            Log.d(TAG, "ДЛИТЕЛЬНОСТИ: источник=${"%.1f".format(srcSec)} c, wav=${"%.1f".format(wavSec)} c, потеря=" +
                    (if (srcSec > 0) "%.1f".format(srcSec - wavSec) else "?") + " c")
        } catch (e: Exception) {
            Log.w(TAG, "не удалось посчитать длительности", e)
        }
        Log.d(TAG, "WAV written: $outputPath")
    }

    private fun resamplePcm16(input: ByteArray, inRate: Int, inCh: Int, outRate: Int, outCh: Int): ByteArray {
        val inSamples = input.size / 2
        if (inSamples == 0) return ByteArray(0)

        val ratio = inRate.toDouble() / outRate.toDouble()
        val outSamples = kotlin.math.max(1, (inSamples.toDouble() / inCh / ratio).toInt())
        val output = ByteArray(outSamples * outCh * 2)
        val inBuf = ByteBuffer.wrap(input).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()

        for (i in 0 until outSamples) {
            val srcIdx = ((i * ratio).toInt() * inCh).coerceIn(0, inBuf.limit() - 1)
            val left = inBuf.get(srcIdx)
            val right = if (inCh == 2 && srcIdx + 1 < inBuf.limit()) {
                inBuf.get(srcIdx + 1)
            } else left
            val mono = ((left.toInt() + right.toInt()) / 2).toShort()
            
            val outIdx = i * outCh
            output[outIdx * 2] = (mono.toInt() and 0xFF).toByte()
            output[outIdx * 2 + 1] = ((mono.toInt() shr 8) and 0xFF).toByte()
            if (outCh == 2) {
                output[(outIdx + 1) * 2] = output[outIdx * 2]
                output[(outIdx + 1) * 2 + 1] = output[outIdx * 2 + 1]
            }
        }
        return output
    }

 
    /// Потоковая конвертация PCM -> WAV 16 кГц: читаем блоками, ресемплим на лету.
    /// Так память не зависит от длины файла (раньше читали весь PCM сразу — OOM).
    private fun streamToWav16k(tmpPcm: File, outputPath: String, inRate: Int, inCh: Int, outRate: Int, outCh: Int) {
        val ratio = inRate.toDouble() / outRate.toDouble()
        val fos = FileOutputStream(outputPath)
        val header = ByteArray(44)
        fos.write(header) // заголовок допишем в конце, когда узнаем размер данных
        var dataBytes = 0L

        val input = BufferedInputStream(FileInputStream(tmpPcm), 1 shl 20)
        val blockBytes = 1 shl 21 // 2 МБ на блок
        val buf = ByteArray(blockBytes)
        val outBuf = ByteArray(blockBytes * 4 + 64)
        var framesRead = 0L
        var nextSrcFrame = 0.0

        try {
            while (true) {
                val read = input.read(buf)
                if (read <= 0) break
                val frames = read / (inCh * 2)
                if (frames <= 0) continue
                var outN = 0
                val endFrame = framesRead + frames
                while (nextSrcFrame < endFrame) {
                    val local = (nextSrcFrame - framesRead).toInt().coerceIn(0, frames - 1)
                    val base = local * inCh * 2
                    val left = ((buf[base].toInt() and 0xFF) or (buf[base + 1].toInt() shl 8)).toShort()
                    val mono: Short = if (inCh >= 2) {
                        val right = ((buf[base + 2].toInt() and 0xFF) or (buf[base + 3].toInt() shl 8)).toShort()
                        (((left.toInt() + right.toInt()) / 2).toShort())
                    } else left
                    if (outN + 4 > outBuf.size) {
                        fos.write(outBuf, 0, outN)
                        dataBytes += outN
                        outN = 0
                    }
                    outBuf[outN++] = (mono.toInt() and 0xFF).toByte()
                    outBuf[outN++] = ((mono.toInt() shr 8) and 0xFF).toByte()
                    if (outCh == 2) {
                        outBuf[outN++] = outBuf[outN - 2]
                        outBuf[outN++] = outBuf[outN - 1]
                    }
                    nextSrcFrame += ratio
                }
                fos.write(outBuf, 0, outN)
                dataBytes += outN
                framesRead = endFrame
            }
        } finally {
            try { input.close() } catch (_: Exception) {}
        }

        // дописываем корректный заголовок
        val byteRate = outRate * outCh * 2
        val h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        h.put("RIFF".toByteArray())
        h.putInt((dataBytes + 36).toInt())
        h.put("WAVE".toByteArray())
        h.put("fmt ".toByteArray())
        h.putInt(16)
        h.putShort(1.toShort())
        h.putShort(outCh.toShort())
        h.putInt(outRate)
        h.putInt(byteRate)
        h.putShort((outCh * 2).toShort())
        h.putShort(16.toShort())
        h.put("data".toByteArray())
        h.putInt(dataBytes.toInt())
        val raf = RandomAccessFile(outputPath, "rw")
        try {
            raf.seek(0)
            raf.write(h.array())
        } finally {
            raf.close()
        }
        fos.close()
        Log.d(TAG, "streamToWav16k done: $dataBytes bytes of PCM")
    }

    private fun writeWavFile(path: String, pcmData: ByteArray, sampleRate: Int, channels: Int, bitsPerSample: Int) {
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val totalDataLen = pcmData.size + 36
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray())
        header.putInt(totalDataLen)
        header.put("WAVE".toByteArray())
        header.put("fmt ".toByteArray())
        header.putInt(16)
        header.putShort(1.toShort())
        header.putShort(channels.toShort())
        header.putInt(sampleRate)
        header.putInt(byteRate)
        header.putShort((channels * bitsPerSample / 8).toShort())
        header.putShort(bitsPerSample.toShort())
        header.put("data".toByteArray())
        header.putInt(pcmData.size)

        FileOutputStream(File(path)).use { fos ->
            fos.write(header.array())
            fos.write(pcmData)
        }
    }
}
