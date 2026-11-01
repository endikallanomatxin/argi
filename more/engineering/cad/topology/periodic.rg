-- Complete analytic supports and finite cylinders use the same Model and queries
-- as polyhedra. Circular boundaries are single closed edges without vertices.
from_periodic_surface := #(.Scalar: Type: Float) (
    .surface      : g.Surface#(Scalar),
    .cap_cylinder : Bool                = false,
    .height       : Scalar              = 1.0,
    .tolerance    : Scalar              = 0.000001,
    .allocator    : $&Virtual#(Allocator)
) -> (.result: Errable#(Model#(Scalar), BuildErrors)) {

    if is_finite(tolerance).ok == false or tolerance <= 0.0 {
        result = ..error(.reason = ..invalid_tolerance)
        return
    }
    basis :: g.Frame#(Scalar) = (
        .origin = (0.0, 0.0, 0.0)
        .x      = (1.0, 0.0, 0.0)
        .y      = (0.0, 1.0, 0.0)
        .z      = (0.0, 0.0, 1.0)
    )
    radius :: Scalar = 0.0
    extent :: Scalar = 0.0
    cylinder ::= false
    genus :: UIntNative = 0
    match surface {
        ..plane _ {
            result = ..error(.reason = ..invalid_surface)
            return
        }
        ..cylinder c {
            basis = c.frame
            radius = c.radius
            extent = radius + height
            cylinder = true
            if is_finite(height).ok == false or height <= tolerance {
                result = ..error(.reason = ..invalid_surface)
                return
            }
        }
        ..sphere s {
            basis = s.frame
            radius = s.radius
            extent = radius
        }
        ..torus t {
            basis = t.frame
            radius = t.minor_radius
            extent = t.major_radius + radius
            genus = 1
            if is_finite(t.major_radius).ok == false or t.major_radius - radius <= tolerance {
                result = ..error(.reason = ..invalid_surface)
                return
            }
        }
    }
    g.validate_frame#(Scalar)(basis)!
    if is_finite(radius).ok == false or radius <= tolerance {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    if cap_cylinder and cylinder == false {
        result = ..error(.reason = ..invalid_surface)
        return
    }
    -- Conservative world-space bound guarantees finite stored g. It does
    -- not claim that arbitrarily large parameter values can be evaluated safely.
    if [
        is_finite(extent).ok == false
        or is_finite(basis.origin.x + extent).ok == false
        or is_finite(basis.origin.x - extent).ok == false
        or is_finite(basis.origin.y + extent).ok == false
        or is_finite(basis.origin.y - extent).ok == false
        or is_finite(basis.origin.z + extent).ok == false
        or is_finite(basis.origin.z - extent).ok == false
    ] {
        result = ..error(.reason = ..numeric_range)
        return
    }

    points ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator)!
    edges ::= DynamicArray#(Edge)(.allocator = allocator)!
    halfedges ::= DynamicArray#(HalfEdge)(.allocator = allocator)!
    loops ::= DynamicArray#(Loop)(.allocator = allocator)!
    faces ::= DynamicArray#(Face)(.allocator = allocator)!
    pools ::= _GeometryPools#(Scalar)(.allocator = allocator)!
    surfaces ::= DynamicArray#(SurfaceId)(.allocator = allocator)!
    boundary_count :: UIntNative = 0
    if cylinder { boundary_count = 2 }
    push(
        $&faces
        .value     = (.first_loop = (.value = 0), .loop_count = boundary_count, .genus = genus)
        .allocator = allocator
    )!
    _pool_append_face_surface(
        .pools = $&pools, .faces = $&surfaces, .surface = surface, .allocator = allocator
    )!
    if cylinder {
        -- Translate the frame origin along its axis, independently of the radial chart.
        top_frame ::= basis
        top_frame.origin = (
            .x = basis.origin.x + basis.z.x * height
            .y = basis.origin.y + basis.z.y * height
            .z = basis.origin.z + basis.z.z * height
        )
        i :: UIntNative = 0
        while i < 2 {
            circle_frame ::= basis
            if i == 1 { circle_frame = top_frame }
            id ::= i | convert#(.to: HalfEdgeId)(_)
            loop_id ::= i | convert#(.to: LoopId)(_)
            edge_id ::= i | convert#(.to: EdgeId)(_)
            mate :: ?HalfEdgeId = ..none
            if cap_cylinder {
                mate = ..some(
                    .value = [[[i + 2] | convert#(.to: HalfEdgeId)(_)]]
                )
            }
            edge: Edge = (
                .first  = id
                .second = mate
                .curve  = ..some(
                    .value = [i | convert#(.to: CurveId)(_)]
                )
            )
            push($&edges, .value = edge, .allocator = allocator)!
            halfedge: HalfEdge = (
                .origin   = ..none
                .edge     = edge_id
                .next     = id
                .loop     = loop_id
                .reversed = i == 1
            )
            push($&halfedges, .value = halfedge, .allocator = allocator)!
            push($&loops, .value = (.first = id, .count = 1), .allocator = allocator)!
            curve: Curve#(Scalar) = ..circle(
                .value = (.frame = circle_frame, .radius = radius)
            )
            stored_curve ::= _pool_add_curve(
                .pools = $&pools, .curve = curve, .allocator = allocator
            )!
            if stored_curve != [i | convert#(.to: CurveId)(_)] {
                abort
            }
            i = i + 1
        }
        if cap_cylinder {
            i = 0
            while i < 2 {
                id ::= [i + 2] | convert#(.to: HalfEdgeId)(_)
                loop_id ::= [i + 2] | convert#(.to: LoopId)(_)
                edge_id ::= i | convert#(.to: EdgeId)(_)
                halfedge: HalfEdge = (
                    .origin   = ..none
                    .edge     = edge_id
                    .next     = id
                    .loop     = loop_id
                    .reversed = i == 0
                )
                push($&halfedges, .value = halfedge, .allocator = allocator)!
                push($&loops, .value = (.first = id, .count = 1), .allocator = allocator)!
                push(
                    $&faces
                    .value     = (.first_loop = loop_id, .loop_count = 1, .genus = 0)
                    .allocator = allocator
                )!
                plane :: g.Plane#(Scalar) = (.origin = basis.origin, .normal = basis.z)
                if i == 0 {
                    plane.normal = (
                        .x = 0.0 - basis.z.x
                        .y = 0.0 - basis.z.y
                        .z = [0.0 - basis.z.z]
                    )
                } else {
                    plane.origin = top_frame.origin
                }
                cap: g.Surface#(Scalar) = ..plane(.value = plane)
                cap_id ::= _pool_add_surface(
                    .pools = $&pools, .surface = cap, .allocator = allocator
                )!
                push($&surfaces, .value = cap_id, .allocator = allocator)!
                i = i + 1
            }
        }
    }
    connectivity: Topology = (
        ._vertex_count = 0
        ._edges        = ~edges
        ._halfedges    = ~halfedges
        ._loops        = ~loops
        ._faces        = ~faces
        ._closed       = cylinder == false or cap_cylinder
    )
    domain ::= idx.IndexDomain(.allocator = allocator)!
    result = ..ok(
        ._domain               = ~domain
        ._topology             = ~connectivity
        ._points               = ~points
        ._geometry             = ~pools
        ._face_surfaces        = ~surfaces
        ._validation_tolerance = tolerance
    )
}
