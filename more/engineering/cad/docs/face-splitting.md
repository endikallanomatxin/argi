# Splitting a planar face

`topology.split_planar_face` cuts one polygonal planar face into two faces with
one straight segment. Each endpoint is a `BoundaryPoint#(Scalar)`: a source
halfedge ID and a normalized parameter in that halfedge's traversal direction.
The scalar type and allocator are inferred from the model and assumed allocator.

```rg
split ::= t.split_planar_face(
    &model,
    .face = face,
    .start = (.halfedge = first_boundary_use, .parameter = 0.5),
    .end = (.halfedge = second_boundary_use, .parameter = 0.5)
)!
```

Parameters `0` and `1` reuse existing vertices. An interior parameter creates one
vertex and splits the source edge, updating both of its uses if it is shared.
The parameter follows the selected halfedge, including its reversal relative
to the edge's canonical curve direction. Both halfedges must belong to the
selected face's first boundary walk. This includes previously joined hole
contours and either side of an existing bridge. An opposite halfedge belonging
to a neighboring face is rejected even when it describes the same geometric edge.

The result owns a new immutable `model`. `faces` identifies the two resulting
faces; `cut_edge`, `cut_start` and `cut_end` identify the inserted segment and its
endpoints. The cut edge's canonical direction is from `cut_start` to `cut_end`.
Both faces share the original surface ID. The source model is unchanged, including after failed operations.

## Admission contract

The selected face must have polygonal boundaries and genus zero. Concave
polygons are supported when the entire chord lies inside the face. The operation
rejects boundary-following, exterior, self-crossing and degenerate cuts through
the same planar-region predicates used in construction. Winding is checked
against the source boundary, independently of the support plane's normal sign.

Previous bridges are supported. For geometric validation, opposite uses of an
edge within each candidate walk are canceled by ID and the remaining uses are
traced into simple contours. Exactly one exterior and correctly nested holes
must remain. The stored walks retain all bridge uses. A cut can leave a bridge
in one face or turn it into an interface between the two faces. Splitting a
bridge also refines both uses and records both edge images in history.
The resulting faces can be merged again with `merge_coplanar_faces`, retaining
bridges that remain internal and removing those belonging to the face interface.
After fusion, unjoined hole walks may also contain internal bridge pieces.
Their simple contours are extracted with their source-walk correspondence;
hole assignment uses a contour point, while output retains the complete walk.

The cut cannot cross, overlap or touch an existing bridge except at its declared
endpoints. Halfedge occurrences distinguish the selected side at a repeated
vertex. Output-region validation rejects a selection through the wrong side.

Holes are assigned to the resulting face containing them, retaining their
source order within that face. A point of each hole is classified against the
first resulting exterior; both complete regions are then validated for contour
intersection, nesting and winding. A cut that crosses a hole, touches it, or
passes within tolerance is rejected. Classification alone never admits a cut.

The model's stored validation tolerance applies to both output regions.
Interior endpoints within that tolerance of an existing edge endpoint are
rejected rather than silently snapped. Use parameter `0` or `1` to request the
existing vertex. Numerical ambiguity and numeric range errors propagate from
the geometry predicates. Coordinates are interpolated on the original edge;
existing coordinates are preserved and no projection is performed.

Cuts joining different loops, curved boundaries and multiple boundary crossings
are not supported by this operation. Connecting an exterior to an unjoined hole
uses `bridge_planar_face` and does not produce two faces. Other faces, including
faces with holes, analytic supports, vertexless curves and closed periodic faces,
retain their geometry and topology; a neighbor of a split edge receives the
new vertex. A closed input remains closed. After joining a hole into the first
walk, a later cut can separate the face.

## Correspondence and ownership

`split_face_images`, `split_edge_images` and `split_vertex_image` query the
correspondence from source IDs to destination IDs. A face or edge has a first
image and an optional second image. Split edge images follow the original
canonical curve direction. All existing vertex IDs survive. Unchanged edges
and faces have one image; the newly created cut edge has no source entity.
Loop and halfedge correspondence is not exposed.

The corresponding `split_face_handle_images`, `split_edge_handle_images` and
`split_vertex_handle_image` queries accept domain-bound handles. They check
source domain membership and bounds, then bind each result to the output domain.
Raw IDs carry no provenance. The history borrows the source domain, while its
output model can be moved out and used independently of the source lifetime.

## Storage and cost

Existing vertex, edge and face offsets are preserved; additional entities are
appended. Halfedges and loops are rebuilt as contiguous ranges in face order.
Incidence is reconstructed by explicit edge IDs in linear time, with no endpoint
sorting, coordinate welding or search through unrelated faces.

Contour extraction uses flat arrays for edge occurrence lookup, twins,
successors and visitation. It is linear in model edge count plus walk length,
without coordinate matching. The operation copies the model and typed geometry
pools once. Geometry IDs and sharing are preserved, including unused declared
supports and curves. Unsplit explicit curves are preserved; split straight edges
use their vertex endpoints, while old pool entries remain available.

For `V` vertices, `E` edges, `H` halfedges, `F` faces and geometry payload `G`,
connectivity reconstruction takes `O(V + E + H + F + G)` time and storage.
Validation of the selected output regions additionally takes `O(n²)` time for
`n` total boundary vertices, following the existing planar-region implementation.
Hole assignment stores owner and visitation flags per stored hole walk, plus a
source-walk index per extracted contour. It queries one contour point per walk;
each query takes linear time in the first exterior length and allocates no storage.
The fixed two-endpoint history needs constant additional storage.

`g.locate_in_planar_contour` is the allocation-free containment query
used for hole assignment. It expects an already validated simple contour and
returns `inside`, `outside` or `boundary`; it does not validate contour simplicity
or region nesting. Its plane normal is normalized before projection. It retains
the same distance tolerance and arithmetic ambiguity policy as region validation.
