# Periodic surfaces without topological seams

`Model#(Scalar)` represents both polygonal surfaces and analytic periodic faces.
A parameter chart is not a topological cell decomposition: its cuts, poles and
period boundaries do not create model edges or vertices.

```rg
assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
frame ::= g.frame#(Float64)(
    .origin = (.x = 0.0, .y = 0.0, .z = 0.0),
    .axis = (.x = 0.0, .y = 0.0, .z = 1.0)
)!
support: g.Surface#(Float64) = ..torus(
    .frame = frame, .major_radius = 3.0, .minor_radius = 1.0
)
model ::= t.from_periodic_surface(.surface = support)!
```

The constructor copies its input into the owning immutable model. `Scalar` and
the allocator type are inferred; tolerance defaults to `0.000001`. Supply the
allocator explicitly or through a lexical `assume`. Its supported inputs and exact entity counts are:

| Support | Faces | Loops | Edges | Half-edges | Vertices | Closed |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `..sphere(.frame, .radius)` | 1 | 0 | 0 | 0 | 0 | yes |
| `..torus(.frame, .major_radius, .minor_radius)` | 1 | 0 | 0 | 0 | 0 | yes |
| `..cylinder(.frame, .radius)` | 1 | 2 | 2 | 2 | 0 | no |
| Cylinder with `.cap_cylinder = true` | 3 | 4 | 2 | 4 | 0 | yes |

The constructor's `.height` argument (default `1.0`) selects axial distances
`[0, height]` on the unbounded cylinder support. The lateral face comes first;
optional planar disk caps follow at the bottom and top. The two circular edges
are real geometric boundaries. Each is one closed curve without a distinguished
vertex. Caps reuse those edges with opposite half-edge orientations. There are
no longitudinal edges, triangulations or persistent parameter cuts.

Radii and cylinder height must be finite and greater than tolerance. Only ring
tori (`major_radius - minor_radius > tolerance`) are accepted: horn and spindle
tori are singular or self-intersecting and return `invalid_surface`. Passing a
plane or requesting cylinder caps on another support also returns
`invalid_surface`. Zero, negative or nonfinite tolerance is rejected. A frame
must have a finite origin and orthonormal right-handed axes within a
scalar-precision arithmetic guard; `g.frame` creates one from an origin and
nonzero axis. The constructor conservatively checks a world-space extent bound
and returns `numeric_range` if it overflows. These are floating-point analytic
supports, not exact arithmetic or a general solid-certification API.

## Topology and queries

`Face.loop_count` may be zero. `Face.genus` describes the connected trimmed face:
zero for spheres, cylinders and planar regions, one for the complete torus.
Boundary components have no universal outer/hole ordering; planar construction
retains its exterior-first convention. The face record can describe any genus
and boundary count without splitting it into simply connected chart patches.
The current analytic constructors provide the cases above, not arbitrary trimmed
freeform surfaces.

Use `face_loops` to traverse every boundary component, including the empty range
of a closed face. `face_loop` remains a convenience for the first component and
returns `missing_boundary` when none exists. `face_info`, `loop_info`,
`loop_halfedges`, `edge_info`, `opposite`, `entity_counts` and `is_closed` work on
both analytic and polygonal models. Traversal allocates no heap storage.

`HalfEdge.origin` is optional. `halfedge_vertex` returns `missing_vertex` for a
vertexless closed curve. It must not be replaced by an arbitrary point on that
curve. `HalfEdge.reversed` describes direction relative to the edge's canonical
curve; opposite uses have opposite directions. `Edge.curve` identifies optional
owned analytic g. Linear edge geometry is derived from its existing
vertices, so polygonal construction does not allocate duplicate curve data.
Curve IDs, like other entity IDs, are model-local.

`face_surface` returns the actual analytic support. `face_plane` succeeds only
for planar faces and returns `nonplanar_face` for curved faces. `edge_curve`
returns a segment or circle by value; `curve_point` evaluates it at a normalized
parameter in `[0, 1]`. `halfedge_point` applies the half-edge's direction before
evaluation. Endpoint parameter values on a circle coincide geometrically within
floating-point rounding; neither becomes a topological vertex.

Entity counts do not form a polygonal cell decomposition. In particular,
`V - E + F` alone is not the Euler characteristic when faces have non-disk
topology or edges are closed curves without vertices. Algorithms must account
for face genus, boundary components and closed curves explicitly.

## Geometry and parameter charts

`g.surface_periodicity` reports periodic chart directions. `g.surface_point`
evaluates the support, independently of trimming, in the frame's axes:

- Plane: coordinates in an orthonormal basis derived from its normal.
- Cylinder: `u` is the angular coordinate in radians, `v` is axial distance.
- Sphere: `u` is longitude in radians, `v` is latitude (canonical range
  `[-pi/2, pi/2]`). Longitude is periodic; the poles are chart singularities.
- Torus: `u` is the major-circle angle, `v` the tube angle, both in radians.

`g.surface_parameter_domain` provides explicit axis periods, limits and pole
singularities. Evaluation rejects spherical latitude outside its canonical
chart. See [support parameter domains](parameter-domains.md).

Periodic directions have period `2*pi`. `g.circle_point` likewise uses radians.
Evaluation validates support data and rejects nonfinite parameters or overflowing
results. Trigonometric reduction and coordinates use the selected floating-point
precision; exact seam equality and accurate evaluation at arbitrarily large
angles are not promised. Evaluation outside a face's trim is a support query,
not a containment test (including on a disk cap).

No existing operation requires a cut chart. An algorithm needing a nonperiodic
chart must keep its cuts as temporary algorithm data and map results back to the
same face and edges. It must not publish those cuts as permanent topology.
Boolean operations, curve intersections, tessellation and arbitrary trimming
are not implemented by this change.
