# Planar profiles and extrusion

`PlanarProfile#(Scalar)` owns a validated set of analytic regions in one 3D
plane. Regions may be concave and disconnected. Each region has one exterior
contour followed by zero or more hole contours. An island inside a hole is a
separate region. Storage consists of directed segment/circular-arc spans, contour
lengths, region lengths and one orthonormal frame. Point and analytic span inputs
produce this same type. Polygon point inputs omit the repeated closing point.

```rg
m := import("engineering/cad/modeling")
g := import("engineering/cad/geometry")

-- Inside a function receiving .system: System:
assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | Virtual#(Allocator)($&_)
points: [4]g.Point#(Float64) = (
    (.x = 0.0, .y = 0.0, .z = 0.0),
    (.x = 2.0, .y = 0.0, .z = 0.0),
    (.x = 2.0, .y = 1.0, .z = 0.0),
    (.x = 0.0, .y = 1.0, .z = 0.0)
)
profile ::= m.profile_from_contour(.points = view(&points))!
model ::= m.extrude(
    .profile = &profile,
    .displacement = (.x = 0.25, .y = 0.0, .z = 3.0)
)!
```

For multiple contours, use `planar_profile(.points, .contour_lengths,
.region_lengths)`. Points are contiguous per contour, and contours contiguous
per region. For example, contour lengths `(4, 4, 3)` and region lengths `(2, 1)`
describe a quadrilateral with a quadrilateral hole plus a separate triangle.
The constructor copies the input and normalizes winding. Profiles can be reused;
mutating their original input buffers does not change them.

`profile_from_spans(.spans, .contour_lengths, .frame)` constructs one analytic
region with an exterior and optional holes. Spans use local frame coordinates;
the exterior must be counterclockwise and holes clockwise. The constructor checks
the frame, continuity, intersections and nesting before copying the input. It
currently accepts segments and circular arcs. Multiple disconnected regions can
still be constructed through the polygonal input API above.

`profile_brep(&profile)` publishes one open planar B-rep face per region. Curves
remain analytic, and all faces share one plane support. Publication borrows the
profile, so it remains available for another publication or modeling operation.
Faces follow profile region order. Loops follow contour order, and traversal of
each loop begins with its first source span.
`profile_spans`, `profile_contour_lengths` and `profile_region_lengths` return
borrowed views; `profile_frame`, `profile_plane` and `profile_tolerance` expose
the embedding and admission tolerance. `profile_point` evaluates a span's start
in world coordinates; it does not flatten that span.

For selections after publication, `profile_brep_with_history(&profile)` returns
a `ProfilePublication` with `.model` and optional correspondence arrays:

```rg
publication ::= m.profile_brep_with_history(&profile)!
face ::= m.published_profile_face(&publication, .region = 0)!
loop ::= m.published_profile_loop(&publication, .contour = 0)!
use ::= m.published_profile_halfedge(&publication, .span = 0)!
edge ::= t.halfedge_info(&publication.model, .halfedge = use)!.edge
```

Source arguments are zero-based positions in this profile's region, contour and
span views. They are not drawing references or persistent entity identities.
The halfedge records directed traversal, including clockwise holes; its edge
field identifies the 3D edge. Out-of-range source positions return `out_of_bounds`.
Destination IDs belong to `publication.model`, and can be passed to its ordinary
topology queries. A later modeling operation requires its own correspondences.

Publication and history own their storage and can outlive the source profile.
History adds `O(regions + contours + spans)` work and compact ID storage; plain
`profile_brep` does not allocate these maps. Mapping follows topology traversal,
without assuming contiguous halfedge IDs. Geometrically coincident source spans
are never matched by their coordinates.

`Scalar` and allocator type are inferred. Profile tolerance defaults to
`0.000001` in model units; extrusion uses that stored tolerance. Both constructors
and extrusion accept an allocator supplied explicitly or through a lexical `assume`.

Extrusion currently accepts profiles consisting entirely of segments. Curved
profiles return `unsupported_boundary`; they are never discretized implicitly.
The same analytic profile can still be published through `profile_brep`.

Extrusion accepts positive, negative and oblique displacements with a normal
component larger than the tolerance. Each region generates its own closed
volume in the returned `Model`. Caps remain planar faces with hole loops;
there is no implicit triangulation. For `n` profile vertices, `l` contours and
`r` regions, counts are `2n` vertices, `3n` edges, `6n` halfedges, `2l+n` loops
and `2r+n` faces. Original caps come first, then translated caps, then walls.
All faces point outward, including walls facing into holes.

`extrude_with_history` performs the same operation and optionally retains
operation-local correspondences:

```rg
extrusion ::= m.extrude_with_history(
    .profile = &section, .displacement = (.x = 0.25, .y = 0.0, .z = 2.0)
)!
caps ::= m.extrusion_caps(&extrusion, .region = 0)!
wall ::= m.extrusion_wall(&extrusion, .span = span_index)!
```

`caps.start` is the original profile cap and `caps.end` is the displaced cap,
including for negative sweeps. Each directed source span generates one wall,
including hole spans. Keys are positions in the supplied profile's public
region/span views; destination face IDs belong only to `extrusion.model`.
Invalid source positions return `out_of_bounds`. History owns its model and
compact maps and can outlive the profile. Ordinary `extrude` allocates no history.
This is correspondence for one operation, not persistent naming across edits.

`extrusion_contour_walls(&extrusion, .contour = i)` returns a repeatable borrowed
range of wall IDs in profile-span order. It includes exterior and hole contours
across all regions. The range must not outlive the extrusion. Querying a contour
is O(1); traversing its walls is linear and allocates nothing. The optional
history stores one offset per contour plus a terminal offset.

Compose it with sketch selection to avoid assuming a profile contour position:

```rg
image ::= s.profile_contour_image(&selection, .contour = opening)!
for wall in m.extrusion_contour_walls(&extrusion, .contour = image.contour)! {
    -- wall belongs to extrusion.model
}
```

Here `extrusion` must have been built from `selection.profile`. Correspondence
positions do not carry a domain check between unrelated operation results.

Validation rejects nonfinite coordinates, nonplanarity, short edges,
self-intersections, contour intersections or contacts within tolerance,
misplaced or nested holes, and overlapping regions. Input winding is arbitrary.
Geometry errors use `topology.BuildErrors`, including `invalid_region_lengths`,
`intersecting_contours`, and `invalid_region_nesting`. Arithmetic overflow returns
`numeric_range`; collapsed sweeps return `degenerate_face`.

`topology.from_planar_faces` also constructs general planar faces from indexed
contours and face loop counts. Its hole windings must oppose their exterior.
The existing equal-length and any-length constructors retain strict convexity.

Validation currently compares contour segments pairwise: quadratic time in
boundary size. Extrusion uses linear geometry buffers and `O(n log n)` edge
matching, plus repeated planar boundary validation. General face validation uses
scratch allocations per face; storage is released between faces. Final model
storage remains contiguous by entity type. The checks use floating-point
arithmetic and absolute tolerance, without exact predicates. Twist, taper and
curved sweeps are outside this operation.

## Planarity contract

`profile_on_frame(&section, .frame = destination)` creates an owning copy of a
profile on another right-handed orthonormal frame. It retains local analytic
spans, contour and region grouping, tolerance and all source positions. The
original remains usable, and the result can outlive it. This is rigid placement;
scaling, reflection and skew frames are rejected. Publication creates new model
identities even though profile positions correspond directly.

Placement validates the destination frame and copies compact arrays in linear
time and space; it does not rerun contour intersection/nesting admission or
tessellate arcs. World-coordinate arithmetic is checked by subsequent queries
and publication, just as for a profile constructed on that frame directly.

`locate_in_profile(&section, .point = world_point)` classifies a point without
publishing geometry or allocating scratch. It returns `outside`, `inside` with
a region position, or `boundary` with region and contour positions. Exterior
and hole boundaries both count as boundary, within the profile's tolerance.
Segments and circular arcs remain analytic. Regions may be disconnected or
include islands inside another region's hole.

Points farther than the profile tolerance from its support plane are outside;
closer points are projected into its chart. Nonfinite coordinates are rejected.
The query scans boundaries in linear time and uses the existing floating-point
classification policy; it is not an exact predicate or a solid classifier.
Returned positions refer only to the queried profile's public views.

Profile input is approximate 3D data. The constructor infers a deterministic
support plane from the complete point set: the lexicographically smallest point,
the farthest point from it, and the point farthest from their supporting line.
Distance ties use lexicographic coordinates. The plane is centered between the
minimum and maximum signed distances along that normal. This is not a best-fit
or minimum-width-plane search; some inputs may be rejected even if a different
plane would fit them within tolerance.

Every input point must lie within the absolute tolerance of this inferred plane.
Accepted profile points are orthogonally projected before storage. Contour
intersection and nesting checks operate in the same plane. Changing a contour's
starting vertex or the order of the regions does not change the inferred plane
or the projected point set. Winding still determines face orientation.

Projection uses the selected floating-point Scalar, so residual rounding error
is possible; exact coplanarity in machine arithmetic is not promised. The
original off-plane coordinates are not retained by the profile. The indexed
planar-face constructor validates planarity but preserves its supplied model
coordinates; profile normalization is a separate import contract.
