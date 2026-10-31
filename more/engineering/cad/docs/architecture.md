# Architecture

## Source layout

- `geometry/`: scalar-generic points, planes, frames and analytic supports.
- `topology/`: typed IDs, model ownership, queries, construction and validation.
- `topology/topology.rg`: scalar-independent connectivity and face-to-loop ranges.
- `topology/model.rg`: composition of connectivity, point positions and analytic g.
- `topology/periodic.rg`: seam-free analytic models with circular or empty boundaries.
- `topology/iteration.rg`: allocation-free borrowed traversal of face loops and half-edges.
- `geometry/predicates.rg`: internal planarity and strict-convexity checks.
- `geometry/regions.rg`: planar contour intersection and nesting validation.
- `modeling/`: owning planar profiles and extrusion.
- `sketch/`: checked contour references, dimensioned shape builders and explicit
  profile publication to analytic planar B-rep; see [sketches](sketches.md).
- `_examples/`: public API examples grouped by construction, sketches, extrusion, analytic surfaces and face editing; see the [guide](../_examples/README.md).
- `*_test.rg`: tests alongside their implementation, automatically discovered.

## Geometry and connectivity
Model storage is private and immutable after construction. Query results are
copies. `VertexId`, `EdgeId`, `HalfEdgeId`, `LoopId` and `FaceId` are distinct types;
their numeric value is local to the model. IDs are distinct records containing a `.value: UIntNative` field. Construct an
ID with an expected type and a named value, for example `.face = (.value = 0)`. Bounds are checked, but a numerically valid
ID from another model cannot be distinguished. There is no deletion,
compaction, persistence or boolean modeling yet. Analytic periodic support is
described in [periodic surfaces](periodic-surfaces.md).
Explicit curve intervals, per-use p-curves and independent face orientation are
described in [analytic trimming](analytic-trimming.md).

`Model#(Scalar)` owns a scalar-independent `Topology`, point positions, face
supports and sparse analytic edge curves. Connectivity validation operates on
`Topology` without reading g.
The public model queries retain their existing signatures and delegate topology
queries to that component.

Each `Face` explicitly stores `.first_loop` and `.loop_count`, describing a
contiguous range of boundary loops, which may be empty. Planar builders put the
outer loop first; periodic faces have no privileged outer component. `.genus`
records the topology of the trimmed face independently of its support chart.
`face_info` returns this
record; `face_loops` traverses its full range and `face_loop` returns its first
component or `missing_boundary`, without assuming that face and loop IDs coincide.
The convex face constructors use one loop;
`from_planar_faces` supports concave exteriors and multiple hole loops.

Construction packs halfedges in boundary order, but edits may change traversal
without moving records. Walk order is defined by `next`; vertex validation
builds its inverse in a temporary linear buffer. It does not infer adjacency
from physical array positions. Face records need not follow loop storage order.
See [orientation reversal](orientation.md) for its invariants.

For the convex constructors, `polygon_plane` validates its inputs, constructs a candidate plane from the first
three vertices, then checks planarity and strict convexity in separate passes.
If several geometric conditions fail, planarity is checked before convexity.
The predicates remain floating-point checks with the existing absolute tolerance;
this separation does not add exact arithmetic or improve the normal calculation.

## Computational costs
Arrays are separated by entity type, with no heap object per vertex or edge.
Edge matching sorts endpoint pairs in `O(H log H)` time, vertex fan checks take
`O(V + H)`, and strict convexity checks take `O(sum(face_size²))`. Construction
uses `O(V + H + F)` storage. These bounds describe the algorithms, not measured
performance claims.

## Modeling operations

`modeling/` generates geometry and face batches and delegates final ownership and
validation to `topology/`. The first operation is [extrusion](extrusion.md).
The module does not reach into private model storage. The original geometry and
topology modules do not depend on modeling.

See [performance measurements](benchmarks.md) for the native baseline executable
and the distinction between logical payload, capacity and process memory.

General planar construction accepts multiple boundary loops per face. Profile
regions map to separate cap faces; holes remain loops of the same face. A model
may contain disconnected closed components without asserting a single solid.
Profile storage uses contiguous points and contour/region lengths, with explicit
exterior ownership and normalized winding. See [profiles](extrusion.md).

Planar region validation infers its support plane from the complete point set,
with coordinate-based tie-breaking, rather than the first contour corner.
Profile import projects accepted points onto that plane; see the
[planarity contract](extrusion.md#planarity-contract). Convex polygon construction
retains its separate strict input contract.

`geometry/orientation.rg` owns the shared floating-point sign and area guards.
The region validator uses them for crossing and containment decisions; distance
to segments remains a separate tolerance-based contact check. Numerical
ambiguity propagates through geometry and modeling errors, without a fallback
that guesses a side. General model construction retains shared coordinates and
records its validation tolerance; it does not assert exact face-plane incidence.

## Periodic geometry

Analytic supports are tagged values (plane, cylinder, sphere or ring torus).
Faces retain their topology across parameter periods and pole singularities.
A complete sphere or torus has one face without edges or vertices; cylinder
boundaries are single circular edges with no preferred vertex. Half-edge
origins are optional and direction relative to the canonical curve is explicit.
Polygonal edges derive segments from existing point storage; only analytic
curves occupy the sparse curve array indexed by `Edge.curve`. There are no
per-entity heap objects. Analytic construction has constant time and storage
for the fixed-size primitives, independent of angular sampling. It never
approximates curves with polygonal seams.

Only planar constructors use the polygon and region predicates. General support
queries expose analytic geometry; planar-only queries fail explicitly on curved
faces. Boundary iteration accepts empty face ranges and one-edge closed loops.
Any future chart cutting belongs to algorithm-local data, not model topology.

Geometry payloads now live in typed pools owned by the model domain. Faces retain
compact support IDs, allowing several faces to reference one declared support.
The append-only builder and checked domain handles are described in
[model domains and incremental construction](model-builder.md).

`merge_coplanar_faces` reconstructs a model after removing the interface between
two selected planar polygonal faces. It uses flat cancellation masks and ID maps,
preserves typed geometry sharing, and validates the merged region and vertex fans.
Boundary contour extraction is shared with face splitting. It cancels bridge
uses only in the geometric admission view; surviving bridges remain stored and
mapped in the result.
See [face merging](face-merging.md) for history, ownership, admission and costs.

`split_planar_face` inserts a straight chord between points on a planar face's
first boundary walk and assigns its unjoined holes to the resulting regions. Full region validation
rejects crossing, touching and ambiguous cuts.
It refines both uses of each split boundary edge, then rebuilds contiguous loops
and edge incidence directly by ID. Existing vertex, edge and face offsets survive;
new entities are appended. The result owns a separate domain and shares support
IDs between its two new faces. History is explicitly one-to-many. See
[face splitting](face-splitting.md) for admission and complexity.

`bridge_planar_face` connects an exterior contour to one hole without creating
another face. Its bridge edge has two opposite uses in one boundary walk.
Further bridges can branch from that walk. Face splitting extracts simple
geometric contours by canceling opposite uses within each candidate walk;
stored topology retains them. Cuts may turn a bridge into a shared face edge.
See [face bridging](face-bridging.md) for admission, history and limitations.
