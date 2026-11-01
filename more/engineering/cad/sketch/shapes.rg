-- Centered shapes declare complete contours. Their returned references are
-- optional for callers; declaration itself adds the geometry to the builder.
circle := #(.Scalar: Type: Float) (
    .builder   : $&SketchBuilder#(Scalar),
    .diameter  : Scalar,
    .center    : g.ContourPoint#(Scalar)   = (0.0, 0.0),
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(ContourRef, t.BuildErrors)) {
    if is_finite(diameter).ok == false or diameter <= 0.0 {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    radius ::= diameter / 2.0
    start: g.ContourPoint#(Scalar) = (center.x + radius, center.y)
    spans: [1]g.ContourSpan#(Scalar) = (
        (.start = start, .end = start, .center = center, .sweep = 6.283185307179586),
    )
    result = [builder | contour(_, .spans = view(&spans), .allocator = allocator)]
}

rectangle := #(.Scalar: Type: Float) (
    .builder   : $&SketchBuilder#(Scalar),
    .width     : Scalar,
    .height    : Scalar,
    .center    : g.ContourPoint#(Scalar)   = (0.0, 0.0),
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(ContourRef, t.BuildErrors)) {
    if [
        is_finite(width).ok == false
        or is_finite(height).ok == false
        or width <= 0.0
        or height <= 0.0
    ] {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    x ::= width / 2.0
    y ::= height / 2.0
    a: g.ContourPoint#(Scalar) = (center.x - x, center.y - y)
    b: g.ContourPoint#(Scalar) = (center.x + x, center.y - y)
    c: g.ContourPoint#(Scalar) = (center.x + x, center.y + y)
    d: g.ContourPoint#(Scalar) = (center.x - x, center.y + y)
    spans: [4]g.ContourSpan#(Scalar) = (
        (.start = a, .end = b),
        (.start = b, .end = c),
        (.start = c, .end = d),
        (.start = d, .end = a)
    )
    result = [builder | contour(_, .spans = view(&spans), .allocator = allocator)]
}

rounded_rectangle := #(.Scalar: Type: Float) (
    .builder   : $&SketchBuilder#(Scalar),
    .width     : Scalar,
    .height    : Scalar,
    .radius    : Scalar,
    .center    : g.ContourPoint#(Scalar)   = (0.0, 0.0),
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(ContourRef, t.BuildErrors)) {
    if [
        is_finite(width).ok == false
        or is_finite(height).ok == false
        or is_finite(radius).ok == false
        or radius <= 0.0
        or width <= 2.0 * radius
        or height <= 2.0 * radius
    ] {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    x ::= width / 2.0
    y ::= height / 2.0
    a: g.ContourPoint#(Scalar) = (center.x - x + radius, center.y - y)
    b: g.ContourPoint#(Scalar) = (center.x + x - radius, center.y - y)
    c: g.ContourPoint#(Scalar) = (center.x + x, center.y - y + radius)
    d: g.ContourPoint#(Scalar) = (center.x + x, center.y + y - radius)
    e: g.ContourPoint#(Scalar) = (center.x + x - radius, center.y + y)
    f: g.ContourPoint#(Scalar) = (center.x - x + radius, center.y + y)
    h: g.ContourPoint#(Scalar) = (center.x - x, center.y + y - radius)
    k: g.ContourPoint#(Scalar) = (center.x - x, center.y - y + radius)
    quarter: Scalar = 1.5707963267948966
    spans: [8]g.ContourSpan#(Scalar) = (
        (.start = a, .end = b),
        (.start = b, .end = c, .center = (b.x, c.y), .sweep = quarter),
        (.start = c, .end = d),
        (.start = d, .end = e, .center = (e.x, d.y), .sweep = quarter),
        (.start = e, .end = f),
        (.start = f, .end = h, .center = (f.x, h.y), .sweep = quarter),
        (.start = h, .end = k),
        (.start = k, .end = a, .center = (a.x, k.y), .sweep = quarter)
    )
    result = [builder | contour(_, .spans = view(&spans), .allocator = allocator)]
}
