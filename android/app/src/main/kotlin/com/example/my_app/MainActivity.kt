package com.example.my_app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import android.util.Base64
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.FloatBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
	private val executor = Executors.newSingleThreadExecutor()
	private val mainHandler = Handler(Looper.getMainLooper())
	private var session: OrtSession? = null
	private var sessionModelAsset: String? = null
	private var environment: OrtEnvironment? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
			.setMethodCallHandler { call, result ->
				if (call.method != "processTable") {
					result.notImplemented()
					return@setMethodCallHandler
				}
				executor.execute {
					try {
						val payload = call.arguments as Map<*, *>
						val modelAssetPath = payload["modelAssetPath"] as String
						val imagePath = payload["imagePath"] as String
						val tableType = payload["tableType"] as String
						val rotation = payload["rotation"] as Int
						val corners = payload["corners"] as List<*>
						val output = processTable(
							modelAssetPath, imagePath, tableType, rotation, corners
						)
						mainHandler.post { result.success(output) }
					} catch (error: Throwable) {
						mainHandler.post {
							result.error("LOCAL_OCR_FAILED", error.message, null)
						}
					}
				}
			}
	}

	private fun processTable(
		modelAssetPath: String,
		imagePath: String,
		tableType: String,
		rotation: Int,
		corners: List<*>
	): Map<String, Any?> {
		val recognizer = getSession(modelAssetPath)
		val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
		BitmapFactory.decodeFile(imagePath, bounds)
		if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
			throw IllegalArgumentException("Could not open the selected image")
		}
		var sampleSize = 1
		while (maxOf(bounds.outWidth, bounds.outHeight) / sampleSize > 2048) {
			sampleSize *= 2
		}
		val source = BitmapFactory.decodeFile(
			imagePath,
			BitmapFactory.Options().apply { inSampleSize = sampleSize }
		)
			?: throw IllegalArgumentException("Could not open the selected image")
		var rotatedBitmap: Bitmap? = null
		var warpedBitmap: Bitmap? = null
		try {
			val rotated = rotate(source, rotation).also { rotatedBitmap = it }
			val warped = rectify(rotated, corners).also { warpedBitmap = it }
			val questions = if (tableType == "1-4") listOf("1", "2", "3", "4")
				else if (tableType == "5-8") listOf("5", "6", "7", "8")
				else throw IllegalArgumentException("Unsupported table type")
			val xRatios = doubleArrayOf(0.0, 115.0 / 379, 183.0 / 379, 252.0 / 379, 320.0 / 379, 1.0)
			val yRatios = doubleArrayOf(0.0, 96.0 / 526, 150.0 / 526, 202.0 / 526, 255.0 / 526,
				308.0 / 526, 361.0 / 526, 414.0 / 526, 474.0 / 526, 1.0)
			val marks = mutableMapOf<String, MutableMap<String, String>>()
			val details = mutableMapOf<String, MutableMap<String, Map<String, Any?>>>()
			val scores = mutableListOf<Double>()
			val parts = listOf("a", "b", "c", "d", "e", "f", "g")

			questions.forEachIndexed { questionIndex, question ->
				val questionMarks = mutableMapOf<String, String>()
				val questionDetails = mutableMapOf<String, Map<String, Any?>>()
				parts.forEachIndexed { partIndex, part ->
					val x1 = (xRatios[questionIndex + 1] * warped.width).toInt()
					val x2 = (xRatios[questionIndex + 2] * warped.width).toInt()
					val y1 = (yRatios[partIndex + 1] * warped.height).toInt()
					val y2 = (yRatios[partIndex + 2] * warped.height).toInt()
					val padding = maxOf(3, ((minOf(x2 - x1, y2 - y1)) * .07).toInt())
					val cell = Bitmap.createBitmap(
						warped, x1 + padding, y1 + padding,
						x2 - x1 - 2 * padding, y2 - y1 - 2 * padding
					)
					try {
						val cropBytes = ByteArrayOutputStream().use { stream ->
							cell.compress(Bitmap.CompressFormat.PNG, 100, stream)
							stream.toByteArray()
						}
						val empty = isBlank(cell)
						val prediction = if (empty) Prediction("", 0.0) else recognize(recognizer, cell)
						val numeric = prediction.text.matches(Regex("^[0-9]{1,2}$"))
						questionMarks[part] = if (numeric) prediction.text else "N/A"
						scores.add(prediction.confidence)
						questionDetails[part] = mapOf(
							"text" to prediction.text,
							"confidence" to prediction.confidence,
							"needs_review" to (!empty && (!numeric || prediction.confidence < .8)),
							"empty" to empty,
							"reason" to if (empty) "empty_cell" else if (!numeric) "expected_one_or_two_digits" else null,
							"crop_base64" to Base64.encodeToString(cropBytes, Base64.NO_WRAP)
						)
					} finally {
						cell.recycle()
					}
				}
				marks[question] = questionMarks
				details[question] = questionDetails
			}
			return mapOf(
				"tableType" to tableType,
				"questions" to questions,
				"cellMarks" to marks,
				"cellResults" to details,
				"confidenceScore" to scores.average(),
				// java.time.Instant is unavailable on supported Android 7 devices.
				"scannedAt" to SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
					.apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date()),
				"isVerified" to false
			)
		} finally {
			warpedBitmap?.recycle()
			rotatedBitmap?.takeIf { it !== source }?.recycle()
			source.recycle()
		}
	}

	private fun getSession(modelAssetPath: String): OrtSession {
		session?.takeIf { sessionModelAsset == modelAssetPath }?.let { return it }
		synchronized(this) {
			session?.takeIf { sessionModelAsset == modelAssetPath }?.let { return it }
			session?.close()
			session = null
			val env = OrtEnvironment.getEnvironment()
			val assetKey = FlutterInjector.instance().flutterLoader()
				.getLookupKeyForAsset(modelAssetPath)
			environment = env
			OrtSession.SessionOptions().use { options ->
				options.setIntraOpNumThreads(2)
				assets.open(assetKey).use { stream ->
					session = env.createSession(stream.readBytes(), options)
				}
			}
			sessionModelAsset = modelAssetPath
			return session!!
		}
	}

	override fun onDestroy() {
		// Close after in-flight work finishes; never close a running session.
		executor.execute {
			session?.close()
			session = null
		}
		executor.shutdown()
		super.onDestroy()
	}

	private fun rotate(bitmap: Bitmap, degrees: Int): Bitmap {
		if (degrees == 0) return bitmap
		require(degrees == 90 || degrees == 180 || degrees == 270)
		val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
		return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
	}

	private fun rectify(bitmap: Bitmap, rawCorners: List<*>): Bitmap {
		require(rawCorners.size == 4) { "Four table corners are required" }
		val source = FloatArray(8)
		rawCorners.forEachIndexed { index, pair ->
			val point = pair as List<*>
			source[index * 2] = (point[0] as Number).toFloat() * bitmap.width
			source[index * 2 + 1] = (point[1] as Number).toFloat() * bitmap.height
		}
		val destination = floatArrayOf(0f, 0f, 1000f, 0f, 1000f, 1400f, 0f, 1400f)
		val matrix = Matrix()
		check(matrix.setPolyToPoly(source, 0, destination, 0, 4)) {
			"Could not rectify the selected table"
		}
		return Bitmap.createBitmap(1000, 1400, Bitmap.Config.ARGB_8888).also {
			Canvas(it).drawBitmap(bitmap, matrix, Paint(Paint.FILTER_BITMAP_FLAG))
		}
	}

	private fun isBlank(bitmap: Bitmap): Boolean {
		val pixels = IntArray(bitmap.width * bitmap.height)
		bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
		val gray = pixels.map { pixel ->
			(((pixel shr 16) and 255) * 299 + ((pixel shr 8) and 255) * 587 + (pixel and 255) * 114) / 1000
		}.sorted()
		val median = gray[gray.size / 2]
		if (median < 80) return false
		val ink = gray.count { it < median - 30 }
		return ink < maxOf(8, (gray.size * .0015).toInt())
	}

	private fun recognize(ortSession: OrtSession, bitmap: Bitmap): Prediction {
		val resizedWidth = minOf(320, maxOf(1, (bitmap.width * 48f / bitmap.height).toInt()))
		val resized = Bitmap.createScaledBitmap(bitmap, resizedWidth, 48, true)
		val input = FloatArray(3 * 48 * 320) { 1f }
		val pixels = IntArray(resizedWidth * 48)
		resized.getPixels(pixels, 0, resizedWidth, 0, 0, resizedWidth, 48)
		for (y in 0 until 48) {
			for (x in 0 until resizedWidth) {
				val pixel = pixels[y * resizedWidth + x]
				val offset = y * 320 + x
				input[offset] = ((pixel and 255) / 127.5f) - 1f
				input[48 * 320 + offset] = (((pixel shr 8) and 255) / 127.5f) - 1f
				input[2 * 48 * 320 + offset] = (((pixel shr 16) and 255) / 127.5f) - 1f
			}
		}
		if (resized !== bitmap) resized.recycle()
		val env = environment!!
		val tensor = OnnxTensor.createTensor(env, FloatBuffer.wrap(input), longArrayOf(1, 3, 48, 320))
		tensor.use {
			ortSession.run(mapOf("x" to tensor)).use { outputs ->
				@Suppress("UNCHECKED_CAST")
				val logits = outputs[0].value as Array<Array<FloatArray>>
				var previous = 0
				var text = ""
				val confidences = mutableListOf<Float>()
				for (step in logits[0]) {
					var token = 0
					for (index in 1 until step.size) if (step[index] > step[token]) token = index
					if (token != 0 && token != previous) {
						confidences.add(step[token])
						text += if (token in 1..10) (token - 1).toString() else "?"
					}
					previous = token
				}
				return Prediction(text, if (confidences.isEmpty()) 0.0 else confidences.average())
			}
		}
	}

	private data class Prediction(val text: String, val confidence: Double)

	companion object {
		private const val CHANNEL = "com.example.my_app/local_ocr"
	}
}
