# Analytic trimming foundation

Geometry supports, edge intervals and face regions are distinct. A cylinder
support has a frame and radius; the finite periodic-cylinder constructor receives
its height separately. Several faces may share one support without sharing trims.

An edge refers to a curve support and optionally to a parameter interval in the
model's typed pools. Legacy segment and circle edges use `[0, 1]` by default.
Circle parameters measure turns; evaluation converts them to radians. The new
explicit closed-edge path admits one complete period without vertices.
`declare_edge` admits a proper circular or elliptic interval with two explicit endpoint
handles. Several such arcs can share one curve support and form a contour.

A halfedge may refer to a p-curve in its face support's parameter space. The
p-curve parameter follows the canonical edge direction. Halfedge reversal
reverses traversal of both the 3D curve interval and its p-curve. A p-curve can
cross a chart period without introducing an edge at the chart cut.

Face reversal is stored independently of the support. It changes the oriented
face, not the support chart. On a spherical latitude, the boundary direction
relative to face orientation selects the northern or southern region. Inverting
a published face requires reversing both senses, preserving this relation and
its region; changing the face flag alone is not the inversion operation.
See [orientation reversal](orientation.md). Poles are chart singularities, not
automatically topological vertices.

## First admitted construction

The explicit B-rep builder declares supports, curves, closed edges and trimmed
faces using checked handles in one domain. The initial certified trim families
are planar regions with circular exterior and hole contours, and spherical caps
bounded by circular latitudes. Each use has
its own p-curve while both faces can share a single vertexless circular edge.
This constructs a closed hemisphere from a spherical face and a reversed planar
cap without a meridian seam.

The declaration sequence is `BrepBuilder()`, `declare_surface`, `declare_curve`,
`declare_closed_edge` (or `declare_vertex` and `declare_edge`),
`declare_trimmed_face`, then `finish_brep`. The
[construction tests](../topology/brep_builder_test.rg) demonstrate the same
mechanism with both scalar precisions and complementary spherical regions.
Declarations append to entity arrays and geometry pools; edge incidence is
updated directly through its ID. Publication checks all edges in linear time.

`face_contains_parameters` is a chart membership query for admitted caps,
planar regions and cylindrical bands, including their boundaries.
It is not an intersection classifier
or a robust inside/outside predicate for arbitrary spatial points.

Admission compares analytic coefficients over the full interval using the model
tolerance; these remain floating-point checks, not exact predicates or a formal
solid certificate. Point samples are used only in tests. Unsupported
curve/surface combinations are rejected.
Planar loops may mix segment and circular supports through the shared chart-region
validator. Other curve families and general nonplanar regions still require
additional admission capabilities.
The existing polygon builder remains available while the shared admission path
is expanded.
See [circular arcs and planar regions](circular-regions.md) for the construction
contract and current restrictions.
Full elliptic contours on planes and cylindrical bands between oblique planar
sections use the same builder; see [cylindrical trimming](cylinder-trimming.md).

The two incremental builders now use a common geometry-free connectivity
writer, accepting opaque entity IDs and loop lengths. The circular admission
rules are separate from that writer. The shared construction code can express
multiple loops without knowing their geometric supports; publication still
requires admission of the particular g.

`unsupported_parameterization` means the certificate does not support the
parameter encoding, even when it could describe compatible g. It is
distinct from an incompatible admitted trim (`invalid_surface`), an unsupported
boundary family (`unsupported_boundary`) and unresolved arithmetic
(`numerical_ambiguity`). The coefficient validator still uses floating-point
checks; these error categories do not provide exact numerical certification.

## Persistent topology and guarantees

Stored loops are oriented topological walks. They can include opposite uses of
an internal bridge; they need not be simple geometric contours. Algorithms must
extract geometric contours where their predicates require simple regions.
Transient chart cuts and algorithm subdivisions do not become persistent edges
without an explicit topological operation.

Walk traversal follows `HalfEdge.next`, independently of physical array order.
Vertex validation uses a temporary predecessor index, not adjacent array slots.

`face_surface` and `face_plane` return the geometric support. Consumers obtain
the independent orientation from `face_info(...).reversed`; the support's frame
or normal is not rewritten to encode a particular face's orientation.

`is_closed` reports paired edge incidence. It does not certify embeddedness,
absence of self-intersection, consistent nesting of shells or a valid solid.
The explicit construction validates its admitted boundary correspondence;
solid certification remains a separate future capability.
