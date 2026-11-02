# Model domains and incremental construction

A `Model` is an ownership and identity domain. It is independent of files and can
contain several disconnected components. A part or document can own several models;
those application concepts do not change the meaning of a local entity ID.

`ModelBuilder` declares vertices, edges, geometric supports and planar faces. Sharing
is explicit: pass the same vertex handle to several edges, the same edge handle to
several `EdgeUse` values, or the same support handle to several faces. Coordinates
are never welded merely because they are equal or close. Import and welding policies
belong above this mechanism.

Construction is append-only. `finish_model` consumes the builder and publishes an
immutable model after checking face geometry, boundary connectivity, edge incidence
and vertex fans. Declaration order defines vertex, edge and face IDs. This first
incremental API accepts one planar polygonal loop per face; the batch planar-face
API continues to support holes. Analytic constructors use the same geometry pools.

The builder records endpoints, edge uses and face lengths in flat arrays. Publication
builds connectivity in linear time in the number of declarations and uses, without
sorting edges or looking them up by coordinates. Geometric admission still uses the
existing polygon checks, including their intersection costs. Temporary flat arrays
are used for that validation; the point and geometry buffers are transferred rather
than copied into the published model.

## Storage

Faces store `SurfaceId` values. A surface descriptor contains a kind and an index
into a contiguous typed pool of planes, cylinders, spheres or tori. Curves use the
same arrangement for circles and explicit segments. Straight polygonal edges derive
their segment from vertex coordinates instead of storing another coordinate pair.
Public surface and curve queries materialize value unions at the query boundary.

`geometry_storage_info` reports pool counts and logical payload bytes, including the
face-to-surface map. It excludes spare capacity, container headers and allocator
metadata. Empty typed pools currently allocate the minimum `DynamicArray` capacity;
lazy allocation remains a separate optimization.

## Handle guarantees

The separate `storage` module prototypes `Index#(Kind)` and `IndexDomain`. An index
contains an offset and a borrowed reference to a stable domain marker. It does not
borrow a resizable entity buffer. Nominal kinds distinguish vertices, edges, faces
and supports. Membership is checked at runtime and reports `wrong_domain`.

The reference lets Argi track temporal validity: using an index after its domain is
destroyed must be rejected by the compiler. Moving the owning domain preserves its
allocation identity. This is not a proof that two live domain arguments are equal,
and it is not a bounds proof: `bind_index` can bind an arbitrary offset. Storage
consumers must check bounds. The domain marker must remain immutable and alive.

Builder operations return these handles. After publication, `vertex_id`, `edge_id`
and `face_id` validate a handle against the model and return compact local IDs for
existing queries and traversal. Raw IDs remain available for bulk algorithms; they
carry no domain or lifetime guarantee. No per-connection handle overhead is added
to topology arrays.

There is no deletion, slot reuse or generation counter in this append-only domain.
Any future mutable deletion API must establish an additional invalidation policy.

The `usage_model_builder` test in
[`incremental_triangle_test.rg`](../_examples/construction/incremental_triangle_test.rg) is a complete public API
example, including transfer to `Model` and resolution of the original handles.
