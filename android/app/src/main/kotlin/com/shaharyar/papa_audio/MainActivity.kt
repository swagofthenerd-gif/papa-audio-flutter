package com.shaharyar.papa_audio

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.abs

/**
 * MediaStore bridge for the on-phone library. Android indexes every audio file
 * on the device already — querying that index is why native players show the
 * local library instantly (and why we never touch raw file paths, which broke
 * the old RN app under scoped storage).
 *
 * Channel: papa.audio/media_store
 *   hasPermission()            -> Bool
 *   requestPermission()        -> Bool (resolves after the system dialog)
 *   queryTracks()              -> List<Map> (one per music file)
 *   getArt(trackId, albumId, size) -> ByteArray? (JPEG)
 */
// AudioServiceActivity (extends FlutterActivity) hands the engine to
// audio_service / just_audio_background — with a plain FlutterActivity the
// audio plugin throws IllegalStateException and NOTHING ever plays.
class MainActivity : AudioServiceActivity() {
    // Two workers: a burst of artwork requests while fling-scrolling a grid
    // shouldn't queue behind one long decode.
    private val executor = Executors.newFixedThreadPool(2)

    // Waveform extraction decodes whole files (seconds of work) — it gets its
    // own single worker so it can never starve artwork loading.
    private val waveformExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val audioPermission: String
        get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
    }

    override fun onDestroy() {
        // Release the worker pools so a destroyed activity (and any in-flight
        // decode holding a reference to it) doesn't leak across recreation.
        executor.shutdownNow()
        waveformExecutor.shutdownNow()
        super.onDestroy()
    }

    /**
     * Ask for the display's fastest mode at the current resolution (90/120Hz
     * panels default some apps to 60) — scrolling and the player morph animate
     * at full panel speed.
     */
    private fun requestHighRefreshRate() {
        try {
            @Suppress("DEPRECATION")
            val display =
                if (Build.VERSION.SDK_INT >= 30) display else windowManager.defaultDisplay
            val current = display?.mode ?: return
            val best = display.supportedModes
                .filter {
                    it.physicalWidth == current.physicalWidth &&
                        it.physicalHeight == current.physicalHeight
                }
                .maxByOrNull { it.refreshRate } ?: return
            if (best.modeId != current.modeId) {
                window.attributes = window.attributes.apply {
                    preferredDisplayModeId = best.modeId
                }
            }
        } catch (_: Exception) {
            // Not critical — stay on the default mode.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Background task queue: call handling AND reply encoding happen off
        // the platform main thread — a full library payload or a burst of
        // artwork byte arrays never blocks input/vsync. (Perf audit finding.)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val taskQueue = messenger.makeBackgroundTaskQueue()
        MethodChannel(messenger, "papa.audio/media_store",
                StandardMethodCodec.INSTANCE, taskQueue)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasAudioPermission())
                    // Activity.requestPermissions must run on the main thread.
                    "requestPermission" ->
                        mainHandler.post { requestAudioPermission(result) }
                    "queryTracks" -> runAsync(result) { queryTracks() }
                    "getArt" -> {
                        val trackId = call.argument<Number>("trackId")?.toLong() ?: 0L
                        val albumId = call.argument<Number>("albumId")?.toLong() ?: 0L
                        val size = call.argument<Number>("size")?.toInt() ?: 300
                        runAsync(result) { loadArt(trackId, albumId, size) }
                    }
                    "getWaveform" -> {
                        val uri = call.argument<String>("uri") ?: ""
                        val buckets = call.argument<Number>("buckets")?.toInt() ?: 96
                        runOnWaveformThread(result) { extractWaveform(uri, buckets) }
                    }
                    "audioFormat" -> {
                        val uri = call.argument<String>("uri") ?: ""
                        runAsync(result) { extractFormat(uri) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** MediaStore queries and bitmap decoding stay off the main thread. With a
     * TaskQueue channel, replies may be sent from any thread — no main-handler
     * hop, no main-thread codec work. */
    private fun <T> runAsync(result: MethodChannel.Result, body: () -> T) {
        executor.execute {
            try {
                result.success(body())
            } catch (e: Exception) {
                result.error("media_store", e.message, null)
            }
        }
    }

    private fun <T> runOnWaveformThread(result: MethodChannel.Result, body: () -> T) {
        waveformExecutor.execute {
            try {
                result.success(body())
            } catch (e: Exception) {
                result.error("waveform", e.message, null)
            }
        }
    }

    // ── Waveform extraction ─────────────────────────────────────────────────
    // Decodes the whole file to PCM once and keeps the peak amplitude per time
    // bucket. Runs on its own worker; Dart caches the result in SQLite so each
    // track ever pays this cost once.

    /** Probe a track's audio format for the "now playing" quality readout:
     *  mime, sample rate, channels, and PCM bit depth when the container
     *  reports it (FLAC/WAV). Bitrate is read from MediaFormat when present,
     *  else estimated from file size / duration. Runs per-track, on demand. */
    private fun extractFormat(uriStr: String): Map<String, Any>? {
        if (uriStr.isEmpty()) return null
        val extractor = MediaExtractor()
        try {
            if (uriStr.startsWith("content://")) {
                extractor.setDataSource(this, Uri.parse(uriStr), null)
            } else {
                extractor.setDataSource(uriStr.removePrefix("file://"))
            }
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    format = f
                    break
                }
            }
            val fmt = format ?: return null
            val out = HashMap<String, Any>()
            fmt.getString(MediaFormat.KEY_MIME)?.let { out["mime"] = it }
            if (fmt.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                out["sampleRate"] = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            }
            if (fmt.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                out["channels"] = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            }
            var bitrate = 0
            if (fmt.containsKey(MediaFormat.KEY_BIT_RATE)) {
                bitrate = fmt.getInteger(MediaFormat.KEY_BIT_RATE)
            }
            // PCM encoding → bit depth (16 / 24 / 32-float) for lossless.
            if (fmt.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                out["bitDepth"] = when (fmt.getInteger(MediaFormat.KEY_PCM_ENCODING)) {
                    android.media.AudioFormat.ENCODING_PCM_24BIT_PACKED -> 24
                    android.media.AudioFormat.ENCODING_PCM_32BIT -> 32
                    android.media.AudioFormat.ENCODING_PCM_FLOAT -> 32
                    else -> 16
                }
            }
            // Estimate bitrate from size/duration when the container omits it
            // (common for FLAC/lossless).
            val durationUs = if (fmt.containsKey(MediaFormat.KEY_DURATION))
                fmt.getLong(MediaFormat.KEY_DURATION) else 0L
            if (bitrate <= 0 && durationUs > 0 && !uriStr.startsWith("content://")) {
                val size = java.io.File(uriStr.removePrefix("file://")).length()
                if (size > 0) bitrate = ((size * 8.0) / (durationUs / 1_000_000.0)).toInt()
            }
            if (bitrate > 0) out["bitrate"] = bitrate
            return out
        } catch (e: Exception) {
            return null
        } finally {
            extractor.release()
        }
    }

    private fun extractWaveform(uriStr: String, buckets: Int): List<Double>? {
        if (uriStr.isEmpty() || buckets <= 4) return null
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            if (uriStr.startsWith("content://")) {
                extractor.setDataSource(this, Uri.parse(uriStr), null)
            } else {
                extractor.setDataSource(uriStr.removePrefix("file://"))
            }
            var trackIndex = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    trackIndex = i
                    format = f
                    break
                }
            }
            if (trackIndex < 0 || format == null) return null
            val durationUs = format.getLong(MediaFormat.KEY_DURATION)
            if (durationUs <= 0) return null
            extractor.selectTrack(trackIndex)

            codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(format, null, null, 0)
            codec.start()

            val peaks = DoubleArray(buckets)
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            // A corrupt/DRM stream can leave the decoder returning only
            // TRY_AGAIN forever; since this runs on a single shared worker, one
            // bad file would wedge all future waveform requests. Bail after a
            // wall-clock cap so the worker is never permanently blocked.
            val deadline = System.currentTimeMillis() + 20_000
            while (!outputDone) {
                if (System.currentTimeMillis() > deadline) return null
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(5000)
                    if (inIdx >= 0) {
                        val buf = codec.getInputBuffer(inIdx)!!
                        val n = extractor.readSampleData(buf, 0)
                        if (n < 0) {
                            codec.queueInputBuffer(
                                inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIdx, 0, n, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIdx = codec.dequeueOutputBuffer(info, 5000)
                if (outIdx >= 0) {
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                    val out = codec.getOutputBuffer(outIdx)
                    if (out != null && info.size > 0) {
                        val bucket = ((info.presentationTimeUs.toDouble() / durationUs) * buckets)
                            .toInt().coerceIn(0, buckets - 1)
                        // PCM16 max-abs scan, striding to cut work ~8x — peaks
                        // survive striding well enough for a 96-bar display.
                        val shorts = out.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                        var maxAbs = 0
                        var i = 0
                        while (i < shorts.limit()) {
                            val v = abs(shorts.get(i).toInt())
                            if (v > maxAbs) maxAbs = v
                            i += 8
                        }
                        val norm = maxAbs / 32768.0
                        if (norm > peaks[bucket]) peaks[bucket] = norm
                    }
                    codec.releaseOutputBuffer(outIdx, false)
                }
            }
            val mx = peaks.max().coerceAtLeast(0.01)
            return List(buckets) { (peaks[it] / mx).coerceIn(0.04, 1.0) }
        } catch (_: Exception) {
            return null
        } finally {
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            extractor.release()
        }
    }

    // ── Permission ──────────────────────────────────────────────────────────

    private fun hasAudioPermission() =
        checkSelfPermission(audioPermission) == PackageManager.PERMISSION_GRANTED

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.success(false) // dialog already up — don't stack requests
            return
        }
        pendingPermissionResult = result
        // On Android 13+ also ask for POST_NOTIFICATIONS in the same prompt so
        // the media-playback notification/lock-screen controls can show.
        val perms = if (Build.VERSION.SDK_INT >= 33) {
            arrayOf(audioPermission, Manifest.permission.POST_NOTIFICATIONS)
        } else {
            arrayOf(audioPermission)
        }
        requestPermissions(perms, REQ_AUDIO)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_AUDIO) {
            pendingPermissionResult?.success(
                grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            )
            pendingPermissionResult = null
        }
    }

    // ── Library query ───────────────────────────────────────────────────────

    private fun queryTracks(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val base = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val hasGenreCol = Build.VERSION.SDK_INT >= 30 // GENRE joined into Media on R+
        val cols = mutableListOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DATA
        )
        if (hasGenreCol) cols.add(MediaStore.Audio.Media.GENRE)
        contentResolver.query(base, cols.toTypedArray(), MediaStore.Audio.Media.IS_MUSIC + " != 0", null, null)
            ?.use { c ->
                val iId = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val iTitle = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val iArtist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val iAlbum = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val iAlbumId = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
                val iDur = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val iTrack = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
                val iYear = c.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
                val iDate = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                val iData = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val iGenre = if (hasGenreCol) c.getColumnIndex(MediaStore.Audio.Media.GENRE) else -1
                while (c.moveToNext()) {
                    val id = c.getLong(iId)
                    // TRACK packs disc + track as disc*1000 + n (e.g. 2003 = disc 2 track 3).
                    val rawTrack = c.getInt(iTrack)
                    out.add(
                        mapOf(
                            "id" to id,
                            "title" to c.getString(iTitle),
                            "artist" to c.getString(iArtist),
                            "album" to c.getString(iAlbum),
                            "albumId" to c.getLong(iAlbumId),
                            "durationMs" to c.getLong(iDur),
                            "track" to rawTrack % 1000,
                            "disc" to if (rawTrack >= 1000) rawTrack / 1000 else 1,
                            "year" to c.getInt(iYear),
                            "genre" to if (iGenre >= 0) c.getString(iGenre) else null,
                            "dateAdded" to c.getLong(iDate),
                            "path" to c.getString(iData),
                            "uri" to ContentUris.withAppendedId(base, id).toString()
                        )
                    )
                }
            }
        return out
    }

    // ── Artwork ─────────────────────────────────────────────────────────────

    private fun loadArt(trackId: Long, albumId: Long, size: Int): ByteArray? {
        // Android 10+: the supported path — a thumbnail of the track itself.
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, trackId)
                return compress(contentResolver.loadThumbnail(uri, Size(size, size), null))
            } catch (_: Exception) {
                // fall through to the legacy albumart URI
            }
        }
        return try {
            val artUri = Uri.parse("content://media/external/audio/albumart/$albumId")
            contentResolver.openInputStream(artUri)?.use { input ->
                val raw = BitmapFactory.decodeStream(input) ?: return null
                compress(scaleDown(raw, size))
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun scaleDown(src: Bitmap, maxSide: Int): Bitmap {
        val longest = maxOf(src.width, src.height)
        if (longest <= maxSide) return src
        val ratio = maxSide.toFloat() / longest
        return Bitmap.createScaledBitmap(
            src,
            (src.width * ratio).toInt().coerceAtLeast(1),
            (src.height * ratio).toInt().coerceAtLeast(1),
            true
        )
    }

    private fun compress(bmp: Bitmap): ByteArray {
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 88, out)
        return out.toByteArray()
    }

    companion object {
        private const val REQ_AUDIO = 7301
    }
}
