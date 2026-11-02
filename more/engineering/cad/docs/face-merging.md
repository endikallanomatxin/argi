# Merging adjacent coplanar faces

`merge_coplanar_faces(&source, .first = a, .second = b)!` joins two distinct
planar polygonal faces of one immutable model. Adjacency means shared topological
edges, not equal or nearby coordinates. The operation removes all their shared
interior edges and retains the exterior boundary, including holes. It performs no
intersection, welding, simplification of collinear corners or coordinate adjustment.

The source remains unchanged. The returned `FaceMerge#(Scalar)` owns its new
`.model` and domain. Both selected faces map to one merged face. Every removed
edge, and every vertex no longer used by any surviving halfedge, has no image.
Other faces and surviving vertices and edges retain declaration order after
compaction. Boundary cycle starting positions are not persistent identities.

## Correspondences and safety

`mapped_face(&operation, .source_face = id)!` returns the destination `FaceId`.
`mapped_vertex` and `mapped_edge` return optional destination IDs: `none` means the
entity was removed. An out-of-range source ID is an error. These are compact raw
IDs with the same model-local contract as the ordinary query API; numeric IDs do
not prove source membership.

`mapped_vertex_handle`, `mapped_edge_handle` and `mapped_face_handle` accept the
checked handles of the source domain. They validate membership before looking up
the correspondence and bind surviving handles to the result domain. Passing a
handle of another live domain reports `wrong_domain`. Using a destination handle
with the original model also reports `wrong_domain`. Vertex and edge handles have
an optional image, while every source face has a destination face.

The operation history borrows the source domain and must not outlive it. Returned
handles borrow the result domain. To keep just the owning result independently of
the source and history, move `~operation.model` out of the operation. Its coordinates,
geometry pools and connectivity own their storage and do not borrow the source.
The `model_merge_result_owns_geometry` test verifies this transfer from a local source.

Halfedge and loop correspondences are not currently exposed. Geometry pool IDs
retain their indices in the copied pools, including declared supports that become
unreferenced; this operation does not garbage-collect a model's geometry domain.
IDs still belong to their respective domains, rather than becoming persistent IDs.

## Admission and rejection

The selected faces must have polygonal boundaries and be coplanar within the
source model's admission tolerance. Coplanarity checks vertex distances against
both source planes. Orientation comes from the face boundaries, independently of
the sign or scale of the stored plane normal. No points are projected or moved.
The merged region is checked by the existing planar-region numerical, intersection
and nesting validation. It may be concave and may preserve, create or fill holes.

Selected faces may contain bridge walks. An edge used twice inside one input
face is retained; it is not part of the interface between the two selected faces.
For geometric validation, opposite uses within each resulting walk are canceled
in a temporary contour view. The resulting simple contours must still describe
exactly one exterior with valid holes. Stored loops retain both bridge uses,
their directions and the surviving edges' history.

This supports bridge → split → merge → split sequences. When a cut has turned
a bridge into an interface between the selected faces, merging removes that
interface normally. When a bridge remains inside one face, merging preserves it.
If filling a hole leaves a bridge ending inside the merged region, the edge and
its endpoint remain explicitly stored. Removing redundant internal edges is a
separate simplification operation, not an implicit part of fusion.
A surviving piece of a refined bridge may belong to a hole walk. Subsequent
cuts extract that walk's geometric contours as well, preserving the internal
piece in stored connectivity.

The operation rejects:

- Invalid face IDs (`out_of_bounds`) and identical arguments (`same_face`).
- Selected curved supports (`nonplanar_face`) and nonlinear or vertexless selected
  boundaries (`unsupported_boundary`). These trims require a different admission
  path; they are never silently replaced with chords.
- Incompatible planes (`not_coplanar`), contrary boundary winding
  (`inconsistent_orientation`) and absence of a shared interface (`not_adjacent`).
- A result without exactly one exterior (`invalid_merge_boundary`), intersecting
  or incorrectly nested contours, nonmanifold vertex fans and numerically
  ambiguous geometry, using the corresponding admission errors.

Unrelated analytic faces retain their supports, curves, orientations, genus and
possibly empty boundary ranges. A closed source stays closed: only paired interior
uses are removed; no surviving boundary edge gains or loses a mate. Allocation
failure destroys partial output and leaves the source unchanged.

## Storage and costs

Implementation uses flat masks and source-to-result index maps. Shared edges are
marked once. Boundary traversal crosses a removed edge through its opposite
halfedge and continues in the adjacent face. New halfedges are emitted contiguously
per loop; connectivity is built directly, without sorting or rebuilding edges by
endpoint coordinates. Explicitly distinct source edges therefore remain distinct.
Geometric contour extraction shares the flat edge-occurrence, twin and successor
arrays used by face splitting. The edge lookup is initialized once for all
selected walks, including holes; extraction is linear in model edge count plus
selected boundary length. The geometric view never replaces stored connectivity.

The model owns copied typed geometry pools, preserving support sharing rather than
creating one surface union per face. Copying is necessary while source and result
own independent storage; this API does not introduce reference counting or shared
ownership of buffers. Construction and scratch storage are linear in source
connectivity and geometry sizes, apart from the existing geometric admission
checks and their intersection costs. There is no constant-time modification claim.

See `usage_merge_coplanar_faces` in
[`merge_faces_test.rg`](../_examples/face_editing/merge_faces_test.rg) for a complete public API example.
