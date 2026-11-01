SurfaceId := (.value: UIntNative)

implement ImplicitlyCopyable#(SurfaceId) ()

-- Descriptors contain only kind and index; payloads live in typed pools.
_SurfaceRef := (.kind: UInt8, .index: UIntNative)

_CurveRef := (.kind: UInt8, .index: UIntNative)

implement ImplicitlyCopyable#(_SurfaceRef) ()

implement ImplicitlyCopyable#(_CurveRef) ()

_Segment := #(.Scalar: Type: Float) (
    .start : g.Point#(Scalar),
    .end   : g.Point#(Scalar)
)

implement#(.Scalar: Type: Float) ImplicitlyCopyable#(_Segment#(Scalar)) ()

_GeometryPools := #(.Scalar: Type: Float) (
    .surfaces  : DynamicArray#(_SurfaceRef),
    .planes    : DynamicArray#(g.Plane#(Scalar)),
    .cylinders : DynamicArray#(g.Cylinder#(Scalar)),
    .spheres   : DynamicArray#(g.Sphere#(Scalar)),
    .tori      : DynamicArray#(g.Torus#(Scalar)),
    .curves    : DynamicArray#(_CurveRef),
    .segments  : DynamicArray#(_Segment#(Scalar)),
    .circles   : DynamicArray#(g.Circle#(Scalar)),
    .ellipses  : DynamicArray#(g.Ellipse#(Scalar)),
    .intervals : DynamicArray#(CurveInterval#(Scalar)),
    .pcurves   : DynamicArray#(PCurve#(Scalar))
)

_GeometryPoolsInitArgs := #(.Scalar: Type: Float) (
    .allocator : $&Virtual#(Allocator)
)

implement#(.Scalar: Type: Float) Init#(
    _GeometryPools#(Scalar), _GeometryPoolsInitArgs#(Scalar)
) (
    .Result : Type = Errable#(_GeometryPools#(Scalar), BuildErrors)
    .init   = _GeometryPoolsInitArgs#(Scalar) -> (.result: Result) {
        surfaces ::= DynamicArray#(_SurfaceRef)(.allocator = allocator)!
        planes ::= DynamicArray#(g.Plane#(Scalar))(.allocator = allocator)!
        cylinders ::= DynamicArray#(g.Cylinder#(Scalar))(.allocator = allocator)!
        spheres ::= DynamicArray#(g.Sphere#(Scalar))(.allocator = allocator)!
        tori ::= DynamicArray#(g.Torus#(Scalar))(.allocator = allocator)!
        curves ::= DynamicArray#(_CurveRef)(.allocator = allocator)!
        segments ::= DynamicArray#(_Segment#(Scalar))(.allocator = allocator)!
        circles ::= DynamicArray#(g.Circle#(Scalar))(.allocator = allocator)!
        ellipses ::= DynamicArray#(g.Ellipse#(Scalar))(.allocator = allocator)!
        intervals ::= DynamicArray#(CurveInterval#(Scalar))(.allocator = allocator)!
        pcurves ::= DynamicArray#(PCurve#(Scalar))(.allocator = allocator)!
        result = ..ok(
            .surfaces  = ~surfaces
            .planes    = ~planes
            .cylinders = ~cylinders
            .spheres   = ~spheres
            .tori      = ~tori
            .curves    = ~curves
            .segments  = ~segments
            .circles   = ~circles
            .ellipses  = ~ellipses
            .intervals = ~intervals
            .pcurves   = ~pcurves
        )
    }
)

_pool_add_surface := #(.Scalar: Type: Float) (
    .pools: $&_GeometryPools#(Scalar), .surface: g.Surface#(Scalar), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(SurfaceId, BuildErrors)) {

    index ::= length(&pools&.surfaces).count
    if index == integer_limits(.value = index).maximum {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    ensure_capacity(.self = $&pools&.surfaces, .capacity = index + 1, .allocator = allocator)!
    reference :: _SurfaceRef = (.kind = 0, .index = 0)
    match surface {
        ..plane p {
            reference.index = length(&pools&.planes).count
            push($&pools&.planes, .value = p.value, .allocator = allocator)!
        }
        ..cylinder c {
            reference.kind = 1
            reference.index = length(&pools&.cylinders).count
            value: g.Cylinder#(Scalar) = (
                .frame  = c.frame
                .radius = c.radius
            )
            push($&pools&.cylinders, .value = value, .allocator = allocator)!
        }
        ..sphere s {
            reference.kind = 2
            reference.index = length(&pools&.spheres).count
            value: g.Sphere#(Scalar) = (.frame = s.frame, .radius = s.radius)
            push($&pools&.spheres, .value = value, .allocator = allocator)!
        }
        ..torus t {
            reference.kind = 3
            reference.index = length(&pools&.tori).count
            value: g.Torus#(Scalar) = (
                .frame        = t.frame
                .major_radius = t.major_radius
                .minor_radius = t.minor_radius
            )
            push($&pools&.tori, .value = value, .allocator = allocator)!
        }
    }
    push_assume_capacity($&pools&.surfaces, .value = reference)
    result = ..ok(.value = index)
}

_pool_surface := #(.Scalar: Type: Float) (.pools: &_GeometryPools#(Scalar), .surface: SurfaceId) -> (
    .result : Errable#(g.Surface#(Scalar), (..out_of_bounds))
) {
    index ::= surface | convert#(.to: UIntNative)(_)
    reference ::= get(&pools&.surfaces, .index = index)!
    if reference.kind == 0 {
        value: g.Surface#(Scalar) = ..plane(
            .value = get(&pools&.planes, .index = reference.index)!
        )
        result = ..ok value
    } else if reference.kind == 1 {
        c ::= get(&pools&.cylinders, .index = reference.index)!
        value: g.Surface#(Scalar) = ..cylinder(
            .frame  = c.frame
            .radius = c.radius
        )
        result = ..ok value
    } else if reference.kind == 2 {
        s ::= get(&pools&.spheres, .index = reference.index)!
        value: g.Surface#(Scalar) = ..sphere(.frame = s.frame, .radius = s.radius)
        result = ..ok value
    } else {
        t ::= get(&pools&.tori, .index = reference.index)!
        value: g.Surface#(Scalar) = ..torus(
            .frame        = t.frame
            .major_radius = t.major_radius
            .minor_radius = t.minor_radius
        )
        result = ..ok value
    }
}

_pool_add_curve := #(.Scalar: Type: Float) (
    .pools: $&_GeometryPools#(Scalar), .curve: Curve#(Scalar), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(CurveId, BuildErrors)) {

    index ::= length(&pools&.curves).count
    if index == integer_limits(.value = index).maximum {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    ensure_capacity(.self = $&pools&.curves, .capacity = index + 1, .allocator = allocator)!
    reference :: _CurveRef = (.kind = 0, .index = 0)
    match curve {
        ..segment s {
            reference.index = length(&pools&.segments).count
            segment: _Segment#(Scalar) = (.start = s.start, .end = s.end)
            push($&pools&.segments, .value = segment, .allocator = allocator)!
        }
        ..circle c {
            reference.kind = 1
            reference.index = length(&pools&.circles).count
            push($&pools&.circles, .value = c.value, .allocator = allocator)!
        }
        ..ellipse e {
            reference.kind = 2
            reference.index = length(&pools&.ellipses).count
            push($&pools&.ellipses, .value = e.value, .allocator = allocator)!
        }
    }
    push_assume_capacity($&pools&.curves, .value = reference)
    result = ..ok(.value = index)
}

_pool_curve := #(.Scalar: Type: Float) (.pools: &_GeometryPools#(Scalar), .curve: CurveId) -> (
    .result : Errable#(Curve#(Scalar), (..out_of_bounds))
) {
    index ::= curve | convert#(.to: UIntNative)(_)
    reference ::= get(&pools&.curves, .index = index)!
    if reference.kind == 0 {
        s ::= get(&pools&.segments, .index = reference.index)!
        value: Curve#(Scalar) = ..segment(.start = s.start, .end = s.end)
        result = ..ok value
    } else if reference.kind == 1 {
        value: Curve#(Scalar) = ..circle(
            .value = get(&pools&.circles, .index = reference.index)!
        )
        result = ..ok value
    } else {
        value: Curve#(Scalar) = ..ellipse(
            .value = get(&pools&.ellipses, .index = reference.index)!
        )
        result = ..ok value
    }
}

_pool_append_face_surface := #(.Scalar: Type: Float) (
    .pools     : $&_GeometryPools#(Scalar),
    .faces     : $&DynamicArray#(SurfaceId),
    .surface   : g.Surface#(Scalar),
    .allocator : $&Virtual#(Allocator)
) -> (.result: Errable#(Void, BuildErrors)) {

    id ::= _pool_add_surface(.pools = pools, .surface = surface, .allocator = allocator)!
    push(faces, .value = id, .allocator = allocator)!
    result = ..ok Void()
}

-- Logical payload excludes capacity slack, container headers and allocator metadata.
geometry_storage_info := #(.Scalar: Type: Float) (.model: &Model#(Scalar)) -> (
    .surfaces      : UIntNative,
    .planes        : UIntNative,
    .cylinders     : UIntNative,
    .spheres       : UIntNative,
    .tori          : UIntNative,
    .curves        : UIntNative,
    .segments      : UIntNative,
    .circles       : UIntNative,
    .ellipses      : UIntNative,
    .intervals     : UIntNative,
    .pcurves       : UIntNative,
    .payload_bytes : UIntNative
) {
    pools ::= &model&._geometry
    surfaces = length(&pools&.surfaces).count
    planes = length(&pools&.planes).count
    cylinders = length(&pools&.cylinders).count
    spheres = length(&pools&.spheres).count
    tori = length(&pools&.tori).count
    curves = length(&pools&.curves).count
    segments = length(&pools&.segments).count
    circles = length(&pools&.circles).count
    ellipses = length(&pools&.ellipses).count
    intervals = length(&pools&.intervals).count
    pcurves = length(&pools&.pcurves).count
    face_count ::= entity_counts(model).faces
    plane_bytes ::= _pool_type_size#(g.Plane#(Scalar))().bytes
    cylinder_bytes ::= _pool_type_size#(g.Cylinder#(Scalar))().bytes
    sphere_bytes ::= _pool_type_size#(g.Sphere#(Scalar))().bytes
    torus_bytes ::= _pool_type_size#(g.Torus#(Scalar))().bytes
    segment_bytes ::= _pool_type_size#(_Segment#(Scalar))().bytes
    circle_bytes ::= _pool_type_size#(g.Circle#(Scalar))().bytes
    surface_ref_bytes ::= _pool_type_size#(_SurfaceRef)().bytes
    curve_ref_bytes ::= _pool_type_size#(_CurveRef)().bytes
    surface_id_bytes ::= _pool_type_size#(SurfaceId)().bytes
    payload_bytes = [
        surfaces * surface_ref_bytes
        + curves * curve_ref_bytes
        + face_count * surface_id_bytes
    ]
    payload_bytes = payload_bytes + planes * plane_bytes + cylinders * cylinder_bytes
    payload_bytes = payload_bytes + spheres * sphere_bytes + tori * torus_bytes
    payload_bytes = payload_bytes + segments * segment_bytes + circles * circle_bytes
    payload_bytes = [payload_bytes + ellipses * _pool_type_size#(g.Ellipse#(Scalar))().bytes]
    payload_bytes = payload_bytes + intervals * _pool_type_size#(CurveInterval#(Scalar))().bytes
    payload_bytes = payload_bytes + pcurves * _pool_type_size#(PCurve#(Scalar))().bytes
}

_pool_type_size := #(.T: Type) () -> (.bytes: UIntNative) { bytes = size_of(.type = T) }

_copy_geometry_pools := #(.Scalar: Type: Float) (
    .source: &_GeometryPools#(Scalar), .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(_GeometryPools#(Scalar), BuildErrors)) {
    surfaces ::= copy(&source&.surfaces, .allocator = allocator)!
    planes ::= copy(&source&.planes, .allocator = allocator)!
    cylinders ::= copy(&source&.cylinders, .allocator = allocator)!
    spheres ::= copy(&source&.spheres, .allocator = allocator)!
    tori ::= copy(&source&.tori, .allocator = allocator)!
    curves ::= copy(&source&.curves, .allocator = allocator)!
    segments ::= copy(&source&.segments, .allocator = allocator)!
    circles ::= copy(&source&.circles, .allocator = allocator)!
    ellipses ::= copy(&source&.ellipses, .allocator = allocator)!
    intervals ::= copy(&source&.intervals, .allocator = allocator)!
    pcurves ::= copy(&source&.pcurves, .allocator = allocator)!
    result = ..ok(
        .surfaces  = ~surfaces
        .planes    = ~planes
        .cylinders = ~cylinders
        .spheres   = ~spheres
        .tori      = ~tori
        .curves    = ~curves
        .segments  = ~segments
        .circles   = ~circles
        .ellipses  = ~ellipses
        .intervals = ~intervals
        .pcurves   = ~pcurves
    )
}

implement Convert#(UIntNative, SurfaceId) (
    .Result  : Type = SurfaceId
    .convert = (.value: UIntNative) -> (.result: Result) { result = (.value = value) }
)

implement Convert#(SurfaceId, UIntNative) (
    .Result  : Type = UIntNative
    .convert = (.value: SurfaceId) -> (.result: Result) { result = value.value }
)

implement Equal#(SurfaceId, SurfaceId) (
    .equal = (.left: SurfaceId, .right: SurfaceId) -> (.ok: Bool) {
        ok = [left.value == right.value]
    }
)
