package com.shaharyar.papa_audio

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

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
class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val audioPermission: String
        get() = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "papa.audio/media_store")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasAudioPermission())
                    "requestPermission" -> requestAudioPermission(result)
                    "queryTracks" -> runAsync(result) { queryTracks() }
                    "getArt" -> {
                        val trackId = call.argument<Number>("trackId")?.toLong() ?: 0L
                        val albumId = call.argument<Number>("albumId")?.toLong() ?: 0L
                        val size = call.argument<Number>("size")?.toInt() ?: 300
                        runAsync(result) { loadArt(trackId, albumId, size) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** MediaStore queries and bitmap decoding stay off the main thread. */
    private fun <T> runAsync(result: MethodChannel.Result, body: () -> T) {
        executor.execute {
            try {
                val value = body()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("media_store", e.message, null) }
            }
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
        requestPermissions(arrayOf(audioPermission), REQ_AUDIO)
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
