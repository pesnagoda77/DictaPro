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
    private val TAG = "DictaPro"
    private val PACK_NAME = "gigaam_pack"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                            Intent(Settings.ACTION_APP_BATTERY_SETTINGS).apply {
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
                else -> result.notImplemented()
            }
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
