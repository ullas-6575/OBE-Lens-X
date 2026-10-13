package com.example.my_app

import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import kotlin.math.*

/** Contour candidates are accepted only after a perspective-warped grid check. */
object TableDetector {
    // BGR input; Android bitmap conversion lives in the platform adapter. Keeping
    // this core free of Android APIs lets the same native algorithm run in JVM tests.
    fun detect(source: Mat): List<List<Double>>? {
        require(!source.empty() && source.channels() == 3)

        val owned = mutableListOf<Mat>()
        fun mat() = Mat().also { owned.add(it) }
        val contours = mutableListOf<MatOfPoint>()
        try {
            val resized = mat()
            val scale = min(1.0, 2000.0 / max(source.cols(), source.rows()))
            Imgproc.resize(source, resized, Size(), scale, scale, Imgproc.INTER_LINEAR)
            val gray = mat()
            Imgproc.cvtColor(resized, gray, Imgproc.COLOR_BGR2GRAY)
            val binary = mat()
            threshold(gray, binary)
            val closed = mat()
            val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(5.0, 5.0)).also { owned.add(it) }
            Imgproc.morphologyEx(binary, closed, Imgproc.MORPH_CLOSE, kernel)
            Imgproc.findContours(closed, contours, mat(), Imgproc.RETR_LIST, Imgproc.CHAIN_APPROX_SIMPLE)
            val area = resized.cols().toDouble() * resized.rows()
            val candidates = mutableListOf<Pair<Double, Array<Point>>>()
            for (contour in contours.sortedByDescending { Imgproc.contourArea(it) }.take(80)) {
                val contourArea = Imgproc.contourArea(contour)
                if (contourArea < max(1000.0, area * .02)) continue
                val curve = MatOfPoint2f(*contour.toArray())
                val polygon = MatOfPoint2f()
                try {
                    for (tolerance in listOf(.015, .025, .04)) {
                        Imgproc.approxPolyDP(curve, polygon, tolerance * Imgproc.arcLength(curve, true), true)
                        if (polygon.total() != 4L) continue
                        val integerPolygon = MatOfPoint(*polygon.toArray())
                        val convex = try { Imgproc.isContourConvex(integerPolygon) } finally { integerPolygon.release() }
                        if (!convex) continue
                        val raw = polygon.toArray()
                        val cx = raw.map { it.x }.average()
                        val cy = raw.map { it.y }.average()
                        val ordered = raw.sortedBy { atan2(it.y - cy, it.x - cx) }
                        val start = ordered.indices.minByOrNull { ordered[it].x + ordered[it].y }!!
                        val p = Array(4) { ordered[(start + it) % 4] }
                        fun distance(a: Point, b: Point) = hypot(a.x-b.x, a.y-b.y)
                        val ratio = (distance(p[0],p[1])+distance(p[3],p[2])) /
                            (distance(p[0],p[3])+distance(p[1],p[2]))
                        if (ratio <= .25 || ratio >= 1.5) continue
                        if (p[0].x >= p[1].x || p[3].x >= p[2].x || p[0].y >= p[3].y || p[1].y >= p[2].y) continue
                        val score = min(1.0, contourArea / max(1.0, Imgproc.contourArea(polygon))) +
                            contourArea / area - abs(ln(ratio / .7)) * .3
                        if (candidates.none { (_, old) -> p.indices.all { distance(p[it], old[it]) < 8 } }) {
                            candidates.add(score to p)
                        }
                        break
                    }
                } finally { curve.release(); polygon.release() }
            }
            fun select(candidatesToCheck: List<Array<Point>>): Array<Point>? {
                var best: Array<Point>? = null
                var bestScore = Double.NEGATIVE_INFINITY
                for (points in candidatesToCheck) {
                    if (points.any { !it.x.isFinite() || !it.y.isFinite() || it.x < 0 || it.y < 0 ||
                            it.x >= resized.cols() || it.y >= resized.rows() }) continue
                    val from = MatOfPoint2f(*points)
                    val to = MatOfPoint2f(Point(8.0,8.0), Point(1008.0,8.0), Point(1008.0,1408.0), Point(8.0,1408.0))
                    val transform = Imgproc.getPerspectiveTransform(from, to)
                    val warped = Mat()
                    val warpedGray = Mat()
                    try {
                        if (Imgproc.contourArea(from) < 1000.0) continue
                        // Warp unblurred BGR pixels, then grayscale/blur/threshold,
                        // in exactly the same order as Python's _align_template.
                        Imgproc.warpPerspective(resized, warped, transform, Size(1017.0,1417.0),
                            Imgproc.INTER_LINEAR, Core.BORDER_CONSTANT, Scalar(255.0,255.0,255.0))
                        Imgproc.cvtColor(warped, warpedGray, Imgproc.COLOR_BGR2GRAY)
                        val score = gridScore(warpedGray) ?: continue
                        if (score > bestScore) { bestScore = score; best = points }
                    } finally {
                        from.release(); to.release(); transform.release(); warped.release(); warpedGray.release()
                    }
                }
                return best
            }
            // A failed contour check must not disable recovery of broken borders.
            // Both backends validate recovered quadrilaterals with the same grid check.
            val best = select(candidates.sortedByDescending { it.first }.map { it.second })
                ?: select(lineCandidates(binary))
            return best?.map { listOf(it.x / scale / (source.cols()-1), it.y / scale / (source.rows()-1))
                .map { coordinate -> coordinate.coerceIn(0.0, 1.0) } }

        } finally {
            contours.forEach { it.release() }
            owned.forEach { it.release() }
        }
    }

    private val templates = listOf(
        doubleArrayOf(0.0,115.0/379,183.0/379,252.0/379,320.0/379,1.0) to
            doubleArrayOf(0.0,96.0/526,150.0/526,202.0/526,255.0/526,308.0/526,361.0/526,414.0/526,474.0/526,1.0),
        DoubleArray(6) { it * .2 } to
            doubleArrayOf(0.0,100.0/740,180.0/740,260.0/740,340.0/740,420.0/740,500.0/740,580.0/740,660.0/740,1.0))

    private fun threshold(gray: Mat, binary: Mat) {
        val blurred = Mat()
        try {
            Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)
            Imgproc.adaptiveThreshold(blurred, binary, 255.0, Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY_INV, 31, 12.0)
        } finally { blurred.release() }
    }

    private data class Line(val position: Double, val slope: Double, val length: Double)
    private data class Fit(val expected: DoubleArray, val matches: Int, val score: Double)

    private fun median(values: List<Double>): Double {
        val ordered = values.sorted()
        val mid = ordered.size / 2
        return if (ordered.size % 2 == 0) (ordered[mid-1]+ordered[mid])/2 else ordered[mid]
    }

    private fun lineGroups(lines: Mat, vertical: Boolean, h: Int, w: Int): List<Line> {
        val entries = mutableListOf<Line>()
        for (i in 0 until lines.rows()) {
            val line = lines.get(i, 0)
            val dx = line[2]-line[0]
            val dy = line[3]-line[1]
            if (vertical) {
                if (abs(dy) < .25*h || abs(dx) > .5*abs(dy)) continue
                val slope = dx/dy
                entries.add(Line(line[0]+slope*(h/2.0-line[1]), slope, hypot(dx,dy)))
            } else {
                if (abs(dx) < .25*w || abs(dy) > .5*abs(dx)) continue
                val slope = dy/dx
                entries.add(Line(line[1]+slope*(w/2.0-line[0]), slope, hypot(dx,dy)))
            }
        }
        val groups = mutableListOf<MutableList<Line>>()
        for (entry in entries.sortedWith(compareBy<Line> { it.position }.thenBy { it.slope }.thenBy { it.length })) {
            if (groups.isEmpty() || entry.position-groups.last().last().position >= max(4.0,min(h,w)*.008)) {
                groups.add(mutableListOf())
            }
            groups.last().add(entry)
        }
        return groups.map { group -> group.maxByOrNull { it.length }!! }
            .sortedByDescending { it.length }.take(30).sortedBy { it.position }
    }

    private fun fitAxis(lines: List<Line>, ratios: DoubleArray, spanHint: Double, extent: Int): Fit? {
        var best: Fit? = null
        for (i in lines.indices) for (j in i+1 until lines.size) {
            for (a in ratios.indices) for (b in a+1 until ratios.size) {
                val span = (lines[j].position-lines[i].position)/(ratios[b]-ratios[a])
                if (span < .7*spanHint || span > 1.4*spanHint) continue
                val expected = DoubleArray(ratios.size) { lines[i].position-ratios[a]*span+ratios[it]*span }
                // Reject impossible shifted fits before comparing near-tied
                // scores; missing borders must not extrapolate outside the photo.
                if (expected.first() < 0 || expected.last() >= extent) continue
                var matches = 0
                var errorSum = 0.0
                for (position in expected) {
                    var error = Double.POSITIVE_INFINITY
                    for (line in lines) error = min(error, abs(position-line.position))
                    if (error < max(4.0,span*.025)) matches++
                    errorSum += min(error/span,.08)
                }
                val score = matches-errorSum-.2*abs(span/spanHint-1)
                if (best == null || score > best.score) best = Fit(expected, matches, score)
            }
        }
        return best
    }

    private fun lineCandidates(binary: Mat): List<Array<Point>> {
        val lines = Mat()
        try {
            val h = binary.rows()
            val w = binary.cols()
            Imgproc.HoughLinesP(binary, lines, 1.0, Math.PI/720, 35, min(h,w)*.15, 40.0)
            if (lines.empty()) return emptyList()
            val vertical = lineGroups(lines, true, h, w)
            val horizontal = lineGroups(lines, false, h, w)
            if (vertical.size < 3 || horizontal.size < 4) return emptyList()
            val widthHint = median(horizontal.map { it.length }.sortedDescending().take(6))
            val heightHint = median(vertical.map { it.length }.sortedDescending().take(6))
            fun edge(groups: List<Line>, position: Double, isVertical: Boolean): DoubleArray {
                val nearest = groups.minByOrNull { abs(it.position-position) }!!
                val slope = if (abs(nearest.position-position) < 10) nearest.slope else median(groups.map { it.slope })
                return if (isVertical) doubleArrayOf(1.0,-slope,slope*h/2-position)
                    else doubleArrayOf(-slope,1.0,slope*w/2-position)
            }
            fun intersect(a: DoubleArray, b: DoubleArray): Point? {
                val z = a[0]*b[1]-a[1]*b[0]
                if (abs(z) < 1e-6) return null
                return Point((a[1]*b[2]-a[2]*b[1])/z, (a[2]*b[0]-a[0]*b[2])/z)
            }
            val candidates = mutableListOf<Array<Point>>()
            for ((xs,ys) in templates) {
                val xf = fitAxis(vertical,xs,widthHint,w) ?: continue
                val yf = fitAxis(horizontal,ys,heightHint,h) ?: continue
                if (xf.matches < 3 || yf.matches < 4) continue
                val left = edge(vertical,xf.expected.first(),true)
                val right = edge(vertical,xf.expected.last(),true)
                val top = edge(horizontal,yf.expected.first(),false)
                val bottom = edge(horizontal,yf.expected.last(),false)
                val points = listOf(intersect(left,top),intersect(right,top),intersect(right,bottom),intersect(left,bottom))
                if (points.any { it == null }) continue
                val polygon = MatOfPoint(*points.filterNotNull().toTypedArray())
                try {
                    if (Imgproc.isContourConvex(polygon)) candidates.add(points.filterNotNull().toTypedArray())
                } finally { polygon.release() }
            }
            return candidates
        } finally { lines.release() }
    }

    private fun gridScore(gray: Mat): Double? {
        val binary = Mat()
        val vertical = Mat()
        val horizontal = Mat()
        val vk = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(1.0, (gray.rows()/8).toDouble()))
        val hk = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size((gray.cols()/8).toDouble(), 1.0))
        try {
            threshold(gray, binary)
            Imgproc.morphologyEx(binary, vertical, Imgproc.MORPH_OPEN, vk)
            Imgproc.morphologyEx(binary, horizontal, Imgproc.MORPH_OPEN, hk)
            val xs = positions(vertical, true)
            val ys = positions(horizontal, false)
            var best: Double? = null
            for ((xr, yr) in templates) {
                fun match(found: List<Double>, ratios: DoubleArray, span: Double): Pair<Int, Double> {
                    val errors = ratios.map { ratio -> found.minOfOrNull { abs(it-(8+ratio*span))/span } ?: 1.0 }
                    return errors.count { it < .035 } to errors.filter { it < .035 }.sumOf { 1-it/.035 }
                }
                val x = match(xs, xr, 1000.0)
                val y = match(ys, yr, 1400.0)
                if (x.first >= 3 && y.first >= 4) best = max(best ?: 0.0, x.second+y.second)
            }
            return best
        } finally { binary.release(); vertical.release(); horizontal.release(); vk.release(); hk.release() }
    }

    private fun positions(mask: Mat, vertical: Boolean): List<Double> {
        val pixels = ByteArray(mask.rows()*mask.cols())
        mask.get(0,0,pixels)
        val counts = IntArray(if (vertical) mask.cols() else mask.rows())
        for (y in 0 until mask.rows()) for (x in 0 until mask.cols()) {
            if (pixels[y*mask.cols()+x].toInt() != 0) counts[if (vertical) x else y]++
        }
        val minimum = (if (vertical) mask.rows() else mask.cols()) * .35
        val groups = mutableListOf<MutableList<Int>>()
        for (i in counts.indices) if (counts[i] >= minimum) {
            if (groups.isEmpty() || i-groups.last().last() > 3) groups.add(mutableListOf())
            groups.last().add(i)
        }
        return groups.map { Math.rint(it.average()) }
    }
}
