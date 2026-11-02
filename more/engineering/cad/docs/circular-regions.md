# Circular arcs and planar regions

The explicit B-rep builder accepts circular contours assembled from partial
arcs, alongside vertexless full circles. A planar face can have one circular
exterior and multiple circular holes. Holes may be off-center; each must lie
strictly inside the exterior and be separated from all other holes.

## Construction

`declare_vertex` creates a checked vertex identity. `declare_curve` creates a
shared circle support. `declare_edge` associates a proper increasing interval
of that support with explicit start and end vertex handles:

```rg
arc ::= t.declare_edge(
    $&builder, .curve = circle,
    .interval = (.start = 0.875, .end = 1.125),
    .start = a, .end = b
)!
```

Circle parameters measure turns. Intervals may cross a period without splitting
at the chart cut. A proper arc has a span greater than zero and less than one;
its distinct endpoint vertices must match the curve evaluations within the
builder tolerance and must be geometrically separated beyond that tolerance.
A complete vertexless circle continues to use `declare_closed_edge`.
Equal coordinates never implicitly merge distinct vertex IDs.

`declare_trimmed_face` takes a flat borrowed batch of `TrimUse` records and
contour lengths, including the one-contour case:

```rg
boundaries: [4]t.TrimUse#(Float64) = (
    (.edge = exterior_a, .pcurve = exterior_a_uv),
    (.edge = exterior_b, .pcurve = exterior_b_uv),
    (.edge = hole_b, .pcurve = hole_b_uv, .reversed = true),
    (.edge = hole_a, .pcurve = hole_a_uv, .reversed = true)
)
lengths: [2]UIntNative = (2, 2)
t.declare_trimmed_face(
    $&builder, .surface = plane,
    .boundaries = view(&boundaries), .contour_lengths = view(&lengths)
)!
model ::= t.finish_brep(~builder, .require_closed = false)!
```

The first contour is exterior; subsequent contours are holes. Connectivity is
checked by vertex identity, not coordinate proximity. The first and last use
must join, just like any adjacent pair. Every p-curve uses its edge's canonical
parameter direction; `reversed` controls traversal. Opposite face uses may
share the same edge. The model stores incidence in halfedges; the builder's
canonical endpoint table is temporary and is discarded on publication.

## Admission limits

Planar contours may combine arcs from different circle supports and straight
segments. They must form simple closed boundaries, with the exterior and holes
oriented consistently with the face. The shared chart-region validator checks
intersections and nesting; no shared-support or complete-circle requirement is
imposed on a planar contour. Spherical cap boundaries retain their separate
complete-circle certificate.

The certificate compares analytic coefficients over every arc. P-curve angles
must match interval endpoints multiplied by a full turn in radians; equivalent
reparameterizations outside this contract return `unsupported_parameterization`.
Intervals may differ by whole turns when adjacent uses cross the support's
period; choosing a different loop anchor does not introduce a seam.

Planar containment and hole separation use analytic segment/arc intersections
and ray parity. Contacts between separate contours are rejected as
`intersecting_contours`; uncertain numerical constructions can return
`numerical_ambiguity`. These checks are not exact predicates or a solid
certificate. Curves are never polygonized for admission.

The chart membership query includes the modeling-tolerance band around contour
boundaries and excludes hole interiors. Orientation inversion preserves that region. Existing planar
split/merge/bridge operations still reject curved boundaries.

## Storage and cost

Published storage remains compact: one curve ID and interval ID per edge,
optional origin per halfedge, and pooled p-curves. No heap object is allocated
per entity. Face input resolution uses temporary contiguous buffers.

For `U` input uses and `C` contours, planar admission takes `O(U²)` time and
`O(U + C)` temporary storage: sorting edge IDs detects duplicate use, coefficient
checks are linear, and chart validation compares span pairs. It does not
scan all previously declared edges for every face. Publication validates edge
incidence and vertex fans in linear time. Immutable orientation reversal keeps
numeric IDs and the shared geometric supports.

See the [arc construction tests](../topology/brep_faces_test.rg) and
[multiple-hole tests](../topology/brep_region_admission_test.rg) for complete examples.
