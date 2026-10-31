idx := import ("../storage")

-- Publish each profile region as one open planar face on a shared support.
-- All spans stay analytic; connectivity is built by the general B-rep builder.
-- Faces follow region order, loops follow contour order, and each loop's first
-- halfedge corresponds to its first span. History relies on these semantic
-- ordering guarantees, not the physical layout or numeric IDs of halfedges.
profile_brep := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .profile: &PlanarProfile#(Scalar), .allocator: $&Provider
) -> (.result: Errable#(t.Model#(Scalar), t.BrepErrors)) {
    builder ::= t.BrepBuilder#(Scalar)(.tolerance = profile&._tolerance, .allocator = allocator)!
    plane: g.Plane#(Scalar) = (.origin = profile&._frame.origin, .normal = profile&._frame.z)
    support: g.Surface#(Scalar) = ..plane(.value = plane)
    surface ::= builder | t.declare_surface($&_, .surface = support, .allocator = allocator)!
    chart ::= g.frame(.origin = plane.origin, .axis = plane.normal)!
    spans ::= view(&profile&._spans)
    lengths ::= view(&profile&._contour_lengths)
    regions ::= view(&profile&._region_lengths)
    count ::= length(&spans).count
    uses ::= DynamicArray#(t.TrimUse#(Scalar))(.capacity = count, .allocator = allocator)!
    -- Assemble curve/edge batches before borrowing them for face admission.
    span_start :: UIntNative = 0
    loop_index :: UIntNative = 0
    loop_count ::= length(&lengths).count
    while loop_index < loop_count {
        n ::= get(&lengths, .index = loop_index)!
        vertices ::= DynamicArray#(idx.Index#(t.VertexId))(
            .capacity = n, .allocator = allocator
        )!
        first ::= get(&spans, .index = span_start)!
        full ::= [
            n == 1
            and [first.sweep == 6.283185307179586 or first.sweep == -6.283185307179586]
        ]
        if full == false {
            i :: UIntNative = 0
            while i < n {
                vertex ::= t.declare_vertex(
                    $&builder
                    .point = _profile_world_point(
                        .frame = profile&._frame
                        .point = get(&spans, .index = span_start + i)!.start
                    ).value
                    .allocator = allocator
                )!
                push_assume_capacity($&vertices, .value = vertex)
                i = i + 1
            }
        }
        i :: UIntNative = 0
        while i < n {
            use ::= _profile_edge(
                .builder   = $&builder
                .frame     = profile&._frame
                .chart     = chart
                .span      = get(&spans, .index = span_start + i)!
                .vertices  = &vertices
                .index     = i
                .count     = n
                .full      = full
                .allocator = allocator
            )!
            push_assume_capacity($&uses, .value = use)
            i = i + 1
        }
        span_start = span_start + n
        loop_index = loop_index + 1
    }
    use_view ::= view(&uses)
    span_start = 0
    loop_start :: UIntNative = 0
    region_index :: UIntNative = 0
    region_count ::= length(&regions).count
    while region_index < region_count {
        loops ::= get(&regions, .index = region_index)!
        first_use ::= span_start
        l :: UIntNative = 0
        while l < loops {
            span_start = span_start + get(&lengths, .index = loop_start + l)!
            l = l + 1
        }
        boundaries ::= slice(&use_view, .start = first_use, .count = span_start - first_use)!
        contours ::= slice(&lengths, .start = loop_start, .count = loops)!
        t.declare_trimmed_face(
            $&builder
            .surface         = surface
            .boundaries      = boundaries
            .contour_lengths = contours
            .allocator       = allocator
        )!
        loop_start = loop_start + loops
        region_index = region_index + 1
    }
    result = [builder | t.finish_brep(~_, .require_closed = false, .allocator = allocator)]
}

_chart_point := #(.Scalar: Type: Float) (.chart: g.Frame#(Scalar), .point: g.Point#(Scalar)) -> (
    .value : t.ParameterPoint#(Scalar)
) {
    offset ::= g.between(.from = chart.origin, .to = point).result
    value = (
        .u = g.dot(.left = chart.x, .right = offset).value
        .v = g.dot(.left = chart.y, .right = offset).value
    )
}

_profile_edge := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .builder   : $&t.BrepBuilder#(Scalar),
    .frame     : g.Frame#(Scalar),
    .chart     : g.Frame#(Scalar),
    .span      : g.ContourSpan#(Scalar),
    .vertices  : &DynamicArray#(idx.Index#(t.VertexId)),
    .index     : UIntNative,
    .count     : UIntNative,
    .full      : Bool,
    .allocator : $&Provider
) -> (.result: Errable#(t.TrimUse#(Scalar), t.BrepErrors)) {
    start ::= _profile_world_point(.frame = frame, .point = span.start).value
    end ::= _profile_world_point(.frame = frame, .point = span.end).value
    curve :: t.Curve#(Scalar) = ..segment(.start = start, .end = end)
    pcurve :: t.PCurve#(Scalar) = ..line(
        .start = _chart_point(.chart = chart, .point = start).value
        .end   = _chart_point(.chart = chart, .point = end).value
    )
    interval :: t.CurveInterval#(Scalar) = (.start = 0.0, .end = 1.0)
    if span.sweep != 0.0 {
        dx ::= span.start.x - span.center.x
        dy ::= span.start.y - span.center.y
        radius ::= hypot(.left = dx, .right = dy).result
        x: g.Displacement#(Scalar) = (
            .x = [frame.x.x * dx + frame.y.x * dy] / radius
            .y = [frame.x.y * dx + frame.y.y * dy] / radius
            .z = [frame.x.z * dx + frame.y.z * dy] / radius
        )
        sign :: Scalar = 1.0
        sweep ::= span.sweep
        if sweep < 0.0 { sign = -1.0 }
        y: g.Displacement#(Scalar) = (
            .x = sign * [frame.y.x * dx - frame.x.x * dy] / radius
            .y = sign * [frame.y.y * dx - frame.x.y * dy] / radius
            .z = sign * [frame.y.z * dx - frame.x.z * dy] / radius
        )
        center ::= _profile_world_point(.frame = frame, .point = span.center).value
        basis: g.Frame#(Scalar) = (
            .origin = center
            .x      = x
            .y      = y
            .z      = g.cross(.left = x, .right = y).result
        )
        circle: t.Curve#(Scalar) = ..circle(.value = (.frame = basis, .radius = radius))
        curve = circle
        interval.end = sign * sweep / 6.283185307179586
        cosine: t.ParameterPoint#(Scalar) = (
            .u = [g.dot(.left = chart.x, .right = x).value * radius]
            .v = [g.dot(.left = chart.y, .right = x).value * radius]
        )
        sine: t.ParameterPoint#(Scalar) = (
            .u = [g.dot(.left = chart.x, .right = y).value * radius]
            .v = [g.dot(.left = chart.y, .right = y).value * radius]
        )
        trim: t.PCurve#(Scalar) = ..ellipse(
            .center = _chart_point(.chart = chart, .point = center).value
            .cosine = cosine
            .sine   = sine
            .start  = 0.0
            .end    = [interval.end * 6.283185307179586]
        )
        pcurve = trim
    }
    curve_id ::= builder | t.declare_curve(_, .curve = curve, .allocator = allocator)!
    if full {
        edge ::= builder | t.declare_closed_edge(_, .curve = curve_id, .allocator = allocator)!
        result = ..ok(.edge = edge, .pcurve = pcurve)
        return
    }
    edge ::= t.declare_edge(
        builder
        .curve     = curve_id
        .interval  = interval
        .start     = get(vertices, .index = index)!
        .end       = get(vertices, .index = [[index + 1] % count])!
        .allocator = allocator
    )!
    result = ..ok(.edge = edge, .pcurve = pcurve)
}
