package com.example.my_app

import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import kotlin.math.*

/** Contour candidates are accepted only after a perspective-warped grid check. */
object TableDetector {
    private const val WARP_MARGIN = 96.0
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
            val closed = mat()
            val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(5.0, 5.0)).also { owned.add(it) }
            for (faint in listOf(false,true)) {
                threshold(gray, binary, faint)
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
                contours.forEach { it.release() }
                contours.clear()
                fun select(candidatesToCheck: List<Array<Point>>): Array<Point>? {
                    var best: Array<Point>? = null
                    var bestScore = Double.NEGATIVE_INFINITY
                    for (points in candidatesToCheck) {
                        if (points.any { !it.x.isFinite() || !it.y.isFinite() || it.x < 0 || it.y < 0 ||
                                it.x >= resized.cols() || it.y >= resized.rows() }) continue
                        val from = MatOfPoint2f(*points)
                        val to = MatOfPoint2f(Point(WARP_MARGIN,WARP_MARGIN), Point(1000+WARP_MARGIN,WARP_MARGIN),
                            Point(1000+WARP_MARGIN,1400+WARP_MARGIN), Point(WARP_MARGIN,1400+WARP_MARGIN))
                        val transform = Imgproc.getPerspectiveTransform(from, to)
                        val warped = Mat()
                        val warpedGray = Mat()
                        try {
                            if (Imgproc.contourArea(from) < 1000.0) continue
                            // Warp unblurred BGR pixels, then grayscale/blur/threshold,
                            // in exactly the same order as Python's _align_template.
                            Imgproc.warpPerspective(resized, warped, transform, Size(1001+2*WARP_MARGIN,1401+2*WARP_MARGIN),
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
                // The Grand Total extension can distort a contour. Compare it with
                // the reconstruction from long grid lines before choosing a crop.
                val best = select(candidates.sortedByDescending { it.first }.map { it.second } + lineCandidates(binary))
                if (best != null) return best.map { listOf(it.x / scale / (source.cols()-1), it.y / scale / (source.rows()-1))
                    .map { coordinate -> coordinate.coerceIn(0.0, 1.0) } }
            }
            return null

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

    private fun threshold(gray: Mat, binary: Mat, faint: Boolean = false) {
        val blurred = Mat()
        val background = Mat()
        val normalized = Mat()
        try {
            Imgproc.GaussianBlur(gray, background, Size(0.0, 0.0), 25.0)
            Core.max(background, Scalar(1.0), background)
            Core.divide(gray, background, normalized, 255.0)
            Imgproc.GaussianBlur(normalized, blurred, Size(5.0, 5.0), 0.0)
            Imgproc.adaptiveThreshold(blurred, binary, 255.0, Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY_INV, 31, if (faint) 4.0 else 12.0)
        } finally { blurred.release(); background.release(); normalized.release() }
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
        val fit = best ?: return null
        val span = fit.expected.last()-fit.expected.first()
        val matched = ratios.indices.map { index ->
            val nearest = lines.minByOrNull { abs(it.position-fit.expected[index]) }!!
            index to nearest.position
        }.filter { (index, position) -> abs(position-fit.expected[index]) < max(4.0,span*.025) }
        if (matched.size >= 2) {
            // Use every matched boundary to refine the initial two-line fit.
            val meanRatio = matched.map { ratios[it.first] }.average()
            val meanPosition = matched.map { it.second }.average()
            val refinedSpan = matched.sumOf { (ratios[it.first]-meanRatio)*(it.second-meanPosition) } /
                matched.sumOf { (ratios[it.first]-meanRatio).pow(2) }
            val refined = ratios.map { meanPosition+(it-meanRatio)*refinedSpan }.toDoubleArray()
            if (refined.first()>=0 && refined.last()<extent) return Fit(refined,fit.matches,fit.score)
        }
        return fit
    }

    private fun lineCandidates(binary: Mat, deskew: Boolean = true): List<Array<Point>> {
        val lines = Mat()
        try {
            val h = binary.rows()
            val w = binary.cols()
            Imgproc.HoughLinesP(binary, lines, 1.0, Math.PI/720, 35, min(h,w)*.15, 40.0)
            if (lines.empty()) return emptyList()
            val vertical = lineGroups(lines, true, h, w)
            val horizontal = lineGroups(lines, false, h, w)
            fun edge(groups: List<Line>, expected: Double, isVertical: Boolean, span: Double): DoubleArray {
                var position = expected
                val nearest = groups.minByOrNull { abs(it.position-position) }!!
                val slope = if (abs(nearest.position-position) < max(4.0,span*.04)) {
                    position = nearest.position
                    nearest.slope
                } else median(groups.map { it.slope })
                return if (isVertical) doubleArrayOf(1.0,-slope,slope*h/2-position)
                    else doubleArrayOf(-slope,1.0,slope*w/2-position)
            }
            fun intersect(a: DoubleArray, b: DoubleArray): Point? {
                val z = a[0]*b[1]-a[1]*b[0]
                if (abs(z) < 1e-6) return null
                return Point((a[1]*b[2]-a[2]*b[1])/z, (a[2]*b[0]-a[0]*b[2])/z)
            }
            val candidates = mutableListOf<Array<Point>>()
            if (vertical.size >= 3 && horizontal.size >= 4) {
                val widthHint = median(horizontal.map { it.length }.sortedDescending().take(6))
                val heightHint = median(vertical.map { it.length }.sortedDescending().take(6))
                for ((xs,ys) in templates) {
                    val xf = fitAxis(vertical,xs,widthHint,w) ?: continue
                    val yf = fitAxis(horizontal,ys,heightHint,h) ?: continue
                    if (xf.matches < 3 || yf.matches < 4) continue
                    val left = edge(vertical,xf.expected.first(),true,xf.expected.last()-xf.expected.first())
                    val right = edge(vertical,xf.expected.last(),true,xf.expected.last()-xf.expected.first())
                    val top = edge(horizontal,yf.expected.first(),false,yf.expected.last()-yf.expected.first())
                    val bottom = edge(horizontal,yf.expected.last(),false,yf.expected.last()-yf.expected.first())
                    val points = listOf(intersect(left,top),intersect(right,top),intersect(right,bottom),intersect(left,bottom))
                    if (points.any { it == null }) continue
                    val polygon = MatOfPoint(*points.filterNotNull().toTypedArray())
                    try {
                        if (Imgproc.isContourConvex(polygon)) candidates.add(points.filterNotNull().toTypedArray())
                    } finally { polygon.release() }
                }
            }
            if (deskew) {
                val votes = DoubleArray(45)
                val angles = DoubleArray(lines.rows())
                val lengths = DoubleArray(lines.rows())
                for (i in angles.indices) {
                    val line = lines.get(i, 0)
                    val dx = line[2]-line[0]
                    val dy = line[3]-line[1]
                    angles[i] = ((Math.toDegrees(atan2(dy,dx))+45)%90+90)%90-45
                    lengths[i] = hypot(dx,dy)
                    votes[((angles[i]+45)/2).toInt().coerceIn(0,44)] += lengths[i]
                }
                val peak = -44.0+2*votes.indices.maxByOrNull { votes[it] }!!
                val selected = angles.indices.filter { abs(angles[it]-peak)<5 }
                val angle = selected.sumOf { angles[it]*lengths[it] }/selected.sumOf { lengths[it] }
                if (abs(angle)>5) {
                    val matrix = Imgproc.getRotationMatrix2D(Point(w/2.0,h/2.0),angle,1.0)
                    val upright = Mat()
                    val inverse = Mat()
                    try {
                        val cosine = abs(matrix.get(0,0)[0])
                        val sine = abs(matrix.get(0,1)[0])
                        val width = ceil(w*cosine+h*sine).toInt()
                        val height = ceil(h*cosine+w*sine).toInt()
                        matrix.put(0,2,matrix.get(0,2)[0]+(width-w)/2.0)
                        matrix.put(1,2,matrix.get(1,2)[0]+(height-h)/2.0)
                        Imgproc.warpAffine(binary,upright,matrix,Size(width.toDouble(),height.toDouble()),
                            Imgproc.INTER_LINEAR,Core.BORDER_CONSTANT,Scalar(0.0))
                        Imgproc.invertAffineTransform(matrix,inverse)
                        val coefficients = DoubleArray(6)
                        inverse.get(0,0,coefficients)
                        for (points in lineCandidates(upright,false)) {
                            candidates.add(points.map { p -> Point(
                                coefficients[0]*p.x+coefficients[1]*p.y+coefficients[2],
                                coefficients[3]*p.x+coefficients[4]*p.y+coefficients[5]) }.toTypedArray())
                        }
                    } finally { matrix.release(); upright.release(); inverse.release() }
                }
            }
            return candidates
        } finally { lines.release() }
    }

    private const val GRID_SAMPLES = 17
    private data class Profiles(val centers: DoubleArray, val positions: List<List<Double>>)
    private data class Traces(val values: Array<DoubleArray>, val count: Int, val score: Double)
    private data class Alignment(val score: Double, val xs: DoubleArray, val ys: DoubleArray,
        val vertical: Array<DoubleArray>, val horizontal: Array<DoubleArray>,
        val sampleX: DoubleArray, val sampleY: DoubleArray)

    data class Grid(val image: Mat, val xs: IntArray, val ys: IntArray)

    /** Caller owns the returned BGR image. Curved grid boundaries become straight. */
    fun rectify(source: Mat, points: Array<Point>): Grid {
        require(!source.empty() && source.channels()==3 && points.size==4)
        require(points.all { it.x.isFinite() && it.y.isFinite() && it.x>=0 && it.y>=0 &&
            it.x<source.cols() && it.y<source.rows() }) { "Table corners must be inside the photograph" }
        val from = MatOfPoint2f(*points)
        val polygon = MatOfPoint(*points)
        val to = MatOfPoint2f(Point(WARP_MARGIN,WARP_MARGIN),Point(1000+WARP_MARGIN,WARP_MARGIN),
            Point(1000+WARP_MARGIN,1400+WARP_MARGIN),Point(WARP_MARGIN,1400+WARP_MARGIN))
        val warped = Mat()
        val gray = Mat()
        var transform: Mat? = null
        try {
            require(Imgproc.isContourConvex(polygon) && Imgproc.contourArea(from)>1000) { "Invalid table quadrilateral" }
            transform = Imgproc.getPerspectiveTransform(from,to)
            Imgproc.warpPerspective(source,warped,transform,Size(1001+2*WARP_MARGIN,1401+2*WARP_MARGIN),
                Imgproc.INTER_LINEAR,Core.BORDER_CONSTANT,Scalar(255.0,255.0,255.0))
            Imgproc.cvtColor(warped,gray,Imgproc.COLOR_BGR2GRAY)
            val grid = alignGrid(gray,true) ?: throw IllegalArgumentException("Grid boundaries cross; retake or adjust the photograph")
            return Grid(flatten(warped,grid),grid.xs.map { Math.rint(it).toInt() }.toIntArray(),
                grid.ys.map { Math.rint(it).toInt() }.toIntArray())
        } finally { from.release(); polygon.release(); to.release(); warped.release(); gray.release(); transform?.release() }
    }

    private fun interpolate(positions: DoubleArray, values: DoubleArray, point: Double): Double {
        if (point<=positions.first()) return values.first()
        if (point>=positions.last()) return values.last()
        var i = 0
        while (positions[i+1]<point) i++
        val fraction = (point-positions[i])/(positions[i+1]-positions[i])
        return values[i]+fraction*(values[i+1]-values[i])
    }

    private fun profiles(binary: Mat, vertical: Boolean): Profiles {
        val thick = Mat()
        val mask = Mat()
        val span = if (vertical) binary.rows() else binary.cols()
        val length = max(9,(span/32) or 1).toDouble()
        val dilation = Imgproc.getStructuringElement(Imgproc.MORPH_RECT,
            if (vertical) Size(7.0,1.0) else Size(1.0,7.0))
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT,
            if (vertical) Size(1.0,length) else Size(length,1.0))
        try {
            Imgproc.dilate(binary,thick,dilation)
            Imgproc.morphologyEx(thick,mask,Imgproc.MORPH_OPEN,kernel)
            val centers = DoubleArray(GRID_SAMPLES)
            val found = mutableListOf<List<Double>>()
            for (i in 0 until GRID_SAMPLES) {
                val start = i*span/GRID_SAMPLES
                val end = (i+1)*span/GRID_SAMPLES
                centers[i] = (start+end-1)/2.0
                val strip = if (vertical) mask.rowRange(start,end) else mask.colRange(start,end)
                val contiguous = strip.clone()
                try { found.add(positions(contiguous,vertical)) }
                finally { contiguous.release(); strip.release() }
            }
            return Profiles(centers,found)
        } finally { thick.release(); mask.release(); dilation.release(); kernel.release() }
    }

    private fun traceGrid(profiles: Profiles, expected: DoubleArray, span: Double): Traces {
        var count = 0
        var score = 0.0
        val traces = expected.indices.map { index ->
            val position = expected[index]
            val gap = (max(0,index-1)..min(expected.size-2,index)).minOf { expected[it+1]-expected[it] }
            val radius = max(8.0,gap*.4)
            var predicted = position
            val found = profiles.positions.map { candidates ->
                val nearest = candidates.minByOrNull { abs(it-predicted) }
                if (nearest!=null && abs(nearest-predicted)<radius) { predicted=nearest; nearest }
                else Double.NaN
            }
            val valid = found.indices.filter { found[it].isFinite() }
            if (valid.size>=GRID_SAMPLES*.4) {
                val centers = valid.map { profiles.centers[it] }.toDoubleArray()
                val values = valid.map { found[it] }.toDoubleArray()
                val trace = DoubleArray(GRID_SAMPLES) { interpolate(centers,values,profiles.centers[it]) }
                count++
                score += valid.size.toDouble()/GRID_SAMPLES-min(median(trace.map { abs(it-position) })/span,.08)
                trace
            } else DoubleArray(GRID_SAMPLES) { position }
        }.toTypedArray()
        return Traces(traces,count,score)
    }

    private fun gridScore(gray: Mat): Double? = alignGrid(gray,false)?.score

    private fun alignGrid(gray: Mat, manual: Boolean): Alignment? {
        val binary = Mat()
        try {
            for (faint in listOf(false,true)) {
                threshold(gray, binary, faint)
                val vertical = profiles(binary,true)
                val horizontal = profiles(binary,false)
                var best: Alignment? = null
                for ((xr, yr) in templates) {
                    val xs = xr.map { WARP_MARGIN+it*(gray.cols()-2*WARP_MARGIN-1) }.toDoubleArray()
                    val ys = yr.map { WARP_MARGIN+it*(gray.rows()-2*WARP_MARGIN-1) }.toDoubleArray()
                    val vx = traceGrid(vertical,xs,gray.cols()-2*WARP_MARGIN-1)
                    val hy = traceGrid(horizontal,ys,gray.rows()-2*WARP_MARGIN-1)
                    fun crossing(traces: Array<DoubleArray>): Boolean =
                        (0 until traces.size-1).any { i -> (0 until GRID_SAMPLES).any { traces[i+1][it]-traces[i][it]<15 } }
                    if (crossing(vx.values) || crossing(hy.values)) continue
                    val score = vx.score+hy.score
                    if (((manual && faint) || (vx.count>=3 && hy.count>=4)) && (best==null || score>best.score)) {
                        best = Alignment(score,xs,ys,vx.values,hy.values,horizontal.centers,vertical.centers)
                    }
                }
                if (best != null) return best
            }
            return null
        } finally { binary.release() }
    }

    private fun flatten(image: Mat, grid: Alignment): Mat {
        val h = image.rows()
        val w = image.cols()
        val owned = mutableListOf<Mat>()
        fun mat() = Mat(h,w,CvType.CV_32FC1).also { owned.add(it) }
        val output = Mat()
        try {
            val vertical = grid.vertical.map { trace -> DoubleArray(h) { interpolate(grid.sampleY,trace,it.toDouble()) } }
            val horizontal = grid.horizontal.map { trace -> DoubleArray(w) { interpolate(grid.sampleX,trace,it.toDouble()) } }
            val x = FloatArray(h*w)
            val y = FloatArray(h*w)
            val identityX = FloatArray(h*w)
            val identityY = FloatArray(h*w)
            for (row in 0 until h) for (col in 0 until w) {
                val offset = row*w+col
                var c = 0
                while (c<grid.xs.size-2 && grid.xs[c+1]<col) c++
                val fx = ((col-grid.xs[c])/(grid.xs[c+1]-grid.xs[c])).coerceIn(0.0,1.0)
                x[offset] = (vertical[c][row]+fx*(vertical[c+1][row]-vertical[c][row])).toFloat()
                var r = 0
                while (r<grid.ys.size-2 && grid.ys[r+1]<row) r++
                val fy = ((row-grid.ys[r])/(grid.ys[r+1]-grid.ys[r])).coerceIn(0.0,1.0)
                y[offset] = (horizontal[r][col]+fy*(horizontal[r+1][col]-horizontal[r][col])).toFloat()
                identityX[offset] = col.toFloat()
                identityY[offset] = row.toFloat()
            }
            val baseX = mat().also { it.put(0,0,x) }
            val baseY = mat().also { it.put(0,0,y) }
            val ix = mat().also { it.put(0,0,identityX) }
            val iy = mat().also { it.put(0,0,identityY) }
            var mapX = baseX
            var mapY = baseY
            repeat(2) {
                mapY = mat().also { Imgproc.remap(baseY,it,mapX,iy,Imgproc.INTER_LINEAR,Core.BORDER_REPLICATE) }
                mapX = mat().also { Imgproc.remap(baseX,it,ix,mapY,Imgproc.INTER_LINEAR,Core.BORDER_REPLICATE) }
            }
            Imgproc.remap(image,output,mapX,mapY,Imgproc.INTER_LINEAR,Core.BORDER_CONSTANT,Scalar(255.0,255.0,255.0))
            return output
        } catch (error: Throwable) { output.release(); throw error }
        finally { owned.forEach { it.release() } }
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
