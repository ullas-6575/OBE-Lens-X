import com.example.my_app.TableDetector
import nu.pattern.OpenCV
import org.junit.Assert.*
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import org.opencv.imgcodecs.Imgcodecs
import java.io.File
import kotlin.math.abs

@RunWith(Parameterized::class)
class TableDetectorParityTest(private val name: String, private val expected: String) {
    @Test fun matchesLinuxDetection() {
        val image = Imgcodecs.imread(File(directory, "$name.png").path)
        try {
            assertFalse("Fixture must be readable", image.empty())
            val start = System.nanoTime()
            val actual = TableDetector.detect(image)
            val elapsedMs = (System.nanoTime()-start)/1_000_000
            println("$name: ${elapsedMs}ms (desktop JVM, not a device benchmark)")
            if (expected == "none") {
                assertNull("$name must fall back to manual editing", actual)
            } else {
                assertNotNull("$name must detect the table", actual)
                val wanted = expected.split(',').map { it.toDouble() }
                assertEquals(4, actual!!.size)
                for (i in 0..3) for (axis in 0..1) {
                    // Permit native OpenCV version/rounding differences, measured
                    // in working-image pixels, not a percentage of table size.
                    val extent = (if (axis == 0) image.cols() else image.rows())-1
                    val scale = minOf(1.0,2000.0/maxOf(image.cols(),image.rows()))
                    val error = abs(actual[i][axis]-wanted[i*2+axis])*extent*scale
                    assertTrue("$name corner $i axis $axis differs from Linux by $error pixels", error <= 4.0)
                }
            }
        } finally { image.release() }
    }

    companion object {
        private val directory = File(System.getProperty("detector.fixtures"))
        @JvmStatic @BeforeClass fun loadNativeLibrary() { OpenCV.loadLocally() }
        @JvmStatic @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<String>> = File(directory,"expected.tsv").readLines()
            .filter { it.isNotBlank() }.map { it.split('\t').toTypedArray() }
    }
}
