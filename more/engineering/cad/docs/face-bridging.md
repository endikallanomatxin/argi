# Connecting an exterior to a hole

`topology.bridge_planar_face` inserts a straight segment between the exterior
boundary walk and one unjoined hole of a planar face. The region must have
polygonal boundaries. Existing bridges in the first walk and other holes are
preserved. The first endpoint may lie on a previous bridge or a contour already
joined into that walk, allowing branching bridge trees.

```rg
operation ::= t.bridge_planar_face(
    &source,
    .face = face,
    .exterior = (.halfedge = exterior_use, .parameter = 0.5),
    .hole = (.halfedge = hole_use, .parameter = 0.5)
)!
```

Endpoint parameters follow their source halfedges. Exact `0` and `1` reuse
existing vertices; interior values split the corresponding edge and update
both incident faces, using the same admission tolerance as face splitting.
The `exterior` halfedge must belong to the selected face's first loop; `hole`
must belong to another loop of that face. Reversed roles and foreign loops
are rejected. Periodic supports and nonlinear boundaries are unsupported.

## Topology and geometry

The result owns a new immutable `model` with the same face IDs, points and
support sharing. `face` identifies the edited face; `bridge_edge` identifies
the new edge. Its canonical direction is from `exterior_vertex` to `hole_vertex`.
Both uses of that edge belong to the same face and the same loop, with opposite
directions. The exterior and selected hole become one contiguous boundary walk;
all remaining holes retain their order after it. Face count and genus stay the
same, loop count decreases by one, and edge count increases by one plus any
split boundary edges. Existing vertex, edge and face offsets are preserved.

The boundary walk visits the bridge twice. It is not a simple polygon, and must
not be passed to polygon-only geometry routines. Queries, halfedge traversal,
`split_planar_face`, `merge_coplanar_faces` and further bridges to unjoined holes
accept it. Editing
uses explicit halfedge occurrences to distinguish the sides of a bridge.
A new segment must not cross, overlap or touch an existing bridge except at
its declared endpoints. No implicit seam is added to analytic surfaces.

The bridge must stay in the represented face region. Validation checks the
refined boundary walks for segment intersections and tolerance-level contacts,
then classifies an interior sample using ray parity. Opposite bridge uses
cancel in parity, while remaining obstacles to the proposed segment. Only
the two declared endpoints may meet contour edges; overlap with their incident
edges is rejected. Numeric range and arithmetic ambiguity errors propagate.
Points retain their coordinates; no hole is filled and no surface is duplicated.
A closed input stays closed, and the source is unchanged after success or error.

## History and ownership

`bridge_face_image`, `bridge_vertex_image` and `bridge_edge_images` map source
IDs to output IDs. Faces and vertices have one image. A boundary edge has two
images when split, ordered along its original canonical direction. The bridge
edge has no source entity. Loop and halfedge history is not exposed.

`bridge_face_handle_image`, `bridge_vertex_handle_image` and
`bridge_edge_handle_images` check source domain membership and bounds, and
return handles borrowing the destination domain. The operation's history
borrows the source domain; the output model owns its geometry and may be moved
out independently of the source lifetime. Raw IDs have bounds checks but carry
no domain provenance.

## Costs

The operation reuses the flat edge-refinement and connectivity-emission paths
of face splitting. Connectivity and typed geometry pools are copied once;
edge incidence is rebuilt by ID without coordinate matching. Storage and
reconstruction cost are linear in model size. The source is already validated;
bridge intersection and containment checks are linear in the selected face's
boundary size and allocate no query storage. Splitting the resulting walk uses
the quadratic simple-contour validation described in the face-splitting docs.
