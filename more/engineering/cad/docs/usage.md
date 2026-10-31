# Using the kernel

Import the bundled modules by their `more/` names:

```rg
t := import("engineering/cad/topology")
g := import("engineering/cad/geometry")
m := import("engineering/cad/modeling")
s := import("engineering/cad/sketch")
idx := import("engineering/cad/storage")
```

Runnable examples are organized by topic in the [example guide](../_examples/README.md).
They build a tetrahedron, a quadrilateral cube and a mixed-face pyramid.

## Construction

Two constructors produce an owning oriented polyhedral surface, `Model#(Scalar)`:

- `from_equal_length_faces(...)` accepts `.points` and `.faces`, a borrowed
  view of arrays of vertex indices with a common length (three for triangles).
  The number of faces is determined at runtime; the common face length is a
  compile-time parameter. Use four for quadrilaterals, or another length of at
  least three for larger convex polygons.
- `from_any_length_faces(...)` accepts `.points`, a flat
  `.vertex_indices` buffer and `.face_lengths`. Each length consumes that many
  consecutive indices. For example, `(4, 3)` describes a quadrilateral followed
  by a triangle, consuming exactly seven indices. Lengths may coincide.

Both default to `.tolerance = 0.000001` (in the inferred scalar type) and
`.require_closed = true`. Pass `.require_closed = false` to construct an open
surface, and override the absolute tolerance when the model's scale requires it.
The allocator is supplied explicitly or through a lexical `assume`.
Inputs are
borrowed during construction and copied into the resulting owner; no partial
model is published on failure. The shared implementation reads both formats
directly, without flattening uniform faces or allocating an offsets buffer.
The caller-selected allocator controls all heap allocations.

Scalar precision, the common face length and allocator type are inferred from
the arguments. Compile-time parameters need not be repeated at the call site:

```rg
assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
faces: [4][3]UIntNative = (
    (0, 2, 1), (0, 1, 3), (1, 2, 3), (2, 0, 3)
)
model ::= t.from_equal_length_faces(
    .points = view(&points), .faces = view(&faces)
)!
```

Empty face collections are rejected with `invalid_face_lengths`. Face lengths
below three return `degenerate_face`; lengths must consume exactly the complete
index buffer. Bounds are checked before advancing the cursor to avoid integer
overflow. Neither constructor assumes the faces are triangles. Each
face currently has one outer loop; winding determines its normal. Shared edges must have
opposite directions. Every vertex must be referenced, and its incident faces
must form one cycle or boundary chain. Disconnected components are allowed.

The tolerance is a positive finite absolute distance, in the same units and
scalar type as the points. Each face must be planar within this tolerance and
strictly convex; edges and interior-side distances must exceed the tolerance.
Concave faces, collinear corners, holes and repeated vertex IDs are rejected.
Nonfinite coordinates and overflowing geometric intermediates return errors.
These are floating-point checks, not exact predicates; extreme scales can be
rejected through underflow/overflow and should be rescaled by the caller.

`require_closed = true` additionally rejects boundary edges. Closure is a
topological property: the kernel does not yet detect intersections between
faces, overlapping components, zero enclosed volume, or outward orientation.
It therefore does not certify that the input bounds a valid physical solid.

## Boundary traversal

An edge has one half-edge on a boundary or two oppositely oriented half-edges
where two faces meet. `HalfEdge` describes one oriented use of that edge in a
face loop; `HalfEdgeId` identifies it. Queries use `halfedge_info` and the
`.halfedge` argument; `entity_counts` reports `.halfedges`.

`loop_halfedges` validates a loop ID and returns a borrowed range, with no heap
allocation. Each iteration yields a `HalfEdgeEntry` containing `.id` and a copy
of `.halfedge`. Its `LoopHalfEdges` and `LoopHalfEdgeIterator` types borrow only
connectivity and do not depend on `Scalar`. The range and its cursors must not outlive the model; returned
entries contain values rather than references into its storage.

```rg
boundary_id ::= t.face_loop(&model, .face = (.value = 0))!
for entry in t.loop_halfedges(&model, .loop = boundary_id)! {
    position ::= t.point(&model, .vertex = t.halfedge_vertex(entry.halfedge)!)!
    testing.expect(position.z == 0.0)!
}
```

Each cursor follows `next` in boundary order and stops after one traversal.
Repeated traversal of the range creates independent cursors. As with Argi's
core iterators, calling `next` requires `has_next` to be true.

## General planar faces

`from_planar_faces` accepts `.points`, flat `.vertex_indices`,
`.contour_lengths` and `.face_loop_counts`. Contours are contiguous per face:
the exterior comes first, followed by holes with opposite winding. Concave
exteriors are supported. The equal-length and any-length constructors above
keep their strict convexity contract.

`face_info` reports `.first_loop` and `.loop_count`; `face_loop` returns only the
first, exterior loop for these planar constructors. Use `face_loops` to traverse
all components and `loop_halfedges` to traverse each contour. See [profiles and extrusion](extrusion.md) for
constructing volumes from multiple planar regions.

## Numerical contract

A model's point coordinates are its stored g. A face plane is an
approximation checked against its boundary within the construction tolerance;
it does not replace the boundary coordinates. Indexed constructors preserve
shared coordinates, rather than projecting each incident face independently.
`validation_tolerance(&model).value` reports that construction tolerance. It is
not an accumulated roundoff budget or a guarantee of exact coplanarity.
Operations requiring planar coordinates must use an explicit projection and
validate their generated g. Profile import performs that normalization
as documented in [extrusion](extrusion.md#planarity-contract).

Planar region orientation, segment-crossing signs and containment share an
internal arithmetic policy independent of model-unit tolerance. The predicates
scale determinants to avoid product overflow and reject unresolved signs as
`numerical_ambiguity`. Area orientation uses a guarded sum as well. Definite contact
within geometric tolerance is rejected as `intersecting_contours`.
Increasing geometric tolerance does not select a topological answer for an
unresolved sign. Repeating the calculation at greater precision can help, but
there is no automatic exact fallback. The guards apply to represented projected
coordinates; they do not certify the preceding 3D projection. This is a
conservative floating-point policy, and can reject valid thin configurations.

Segment-distance comparisons also reserve a roundoff margin before deciding
whether contact is inside or outside the geometric tolerance. If that margin
straddles the tolerance threshold, they return `numerical_ambiguity` rather than
reporting a definite contact or separation. These guards are intentionally
conservative and are not interval or exact arithmetic certification.

## Analytic periodic faces

[Periodic surfaces](periodic-surfaces.md) use the same owning `Model`, with
analytic supports and vertexless circular edges. Complete spheres and tori have
one face and no boundary entities. A cylindrical lateral face has two circular
boundaries and no longitudinal seam. Use `face_surface` for general supports,
`face_loops` for potentially empty boundary ranges and `halfedge_point` to
evaluate either linear or circular edge uses. `face_plane` returns
`nonplanar_face` for curved supports; `face_loop` returns `missing_boundary`
when a face has no loops. `halfedge_vertex` explicitly rejects a vertexless
closed edge with `missing_vertex`.
