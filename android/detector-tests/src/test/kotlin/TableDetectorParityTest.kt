import com.example.my_app.TableDetector
import nu.pattern.OpenCV
import org.junit.Assert.*
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.core.Core
import org.opencv.core.Mat
import org.opencv.core.Point
import org.opencv.core.Rect
import java.io.File
import kotlin.math.abs

@RunWith(Parameterized::class)
class TableDetectorParityTest(private val name: String, private val expected: String) {
    @Test fun matchesLinuxCellReconstruction() {
        if (expected == "none") return
        val image = Imgcodecs.imread(File(directory,"$name.png").path)
        val corners = expected.split(',').map { it.toDouble() }
        val points = Array(4) { Point(corners[it*2]*(image.cols()-1), corners[it*2+1]*(image.rows()-1)) }
        try {
            val grid = TableDetector.rectify(image,points)
            try {
                var index = 0
                for (row in 1..7) for (column in 1..4) {
                    val x1 = grid.xs[column]
                    val x2 = grid.xs[column+1]
                    val y1 = grid.ys[row]
                    val y2 = grid.ys[row+1]
                    val pad = maxOf(3,(minOf(x2-x1,y2-y1)*.07).toInt())
                    val cell = grid.image.submat(Rect(x1+pad,y1+pad,x2-x1-2*pad,y2-y1-2*pad))
                    val wanted = Imgcodecs.imread(File(directory,"${name}_cell_${index++}.png").path)
                    val difference = Mat()
                    try {
                        assertEquals("$name cell width",wanted.cols(),cell.cols())
                        assertEquals("$name cell height",wanted.rows(),cell.rows())
                        Core.absdiff(cell,wanted,difference)
                        assertTrue("$name cell $index pixels differ",Core.mean(difference).`val`.take(3).average()<3)
                    } finally { cell.release(); wanted.release(); difference.release() }
                }
                assertEquals(28,index)
            } finally { grid.image.release() }
        } finally { image.release() }
    }

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
