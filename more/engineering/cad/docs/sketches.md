# Sketch builder

Import `sketch` as `s` and `modeling` as `m` to declare dimensioned planar
contours with free functions and Argi's pipe syntax. Coordinates use the sketch's local X/Y
axes. The default plane is XY; XZ and YZ are also supported, with an optional
world origin. Specify `Scalar` when constructing the builder for Float32/Float64.

```rg
assume allocator ::= GeneralPurposeAllocator(system.page_allocator) | to_virtual#(Allocator)($&_)
builder ::= s.SketchBuilder#(Float64)(.plane = ..xy)!
```

The allocator follows ordinary explicit or lexically assumed arguments.

Use `sketch_builder_on_frame(.frame = frame)` for another placement. It infers
`Scalar` from an existing `g.Frame`: origin, local X/Y directions and
normal are preserved through profile selection, publication and extrusion.
The frame must be right-handed and orthonormal. Scale, skew and reflection are
rejected rather than silently changing dimensions or winding.

A planar face can supply the normal and a reference origin for another sketch:

```rg
support ::= t.face_plane(&extrusion.model, .face = caps.end)!
frame ::= g.frame(.origin = support.origin, .axis = support.normal)!
next_sketch ::= s.sketch_builder_on_frame(.frame = frame)!
```

The support origin is not necessarily the face center. Choose a specific origin
or full frame when placement or in-plane rotation matters. This copies geometry;
it does not create a live attachment or clip subsequent contours to that face.

Use `g.frame_from_directions(.origin = origin, .normal = normal,
.x_direction = heading)` to control in-plane rotation. The constructor
normalizes the normal and projects the heading into its plane. Heading length
does not scale sketch dimensions. Parallel or zero directions return
`degenerate_face`; nearly parallel directions return `numerical_ambiguity`
using an angular precision guard independent of modeling tolerance. It never
chooses a replacement heading silently. The resulting frame can be passed
directly to `sketch_builder_on_frame`.
See the [generated-cap example](../_examples/sketches/stacked_sketches_test.rg)
for a complete placement from extrusion history through a second sketch.

`rectangle`, `rounded_rectangle` and `circle` append complete counterclockwise
contours. They return checked `ContourRef` values, which callers may retain or
ignore. A reference belongs to one drawing domain and survives builder growth
and transfer through `finish_sketch`; references to other drawings are rejected.

`contour` accepts explicit directed segment/circular-arc spans for shapes beyond
the convenience constructors. Admission validates each contour before appending
it. Storage consists of one span array and one contour-range array, without
allocating objects per segment. Rejected input does not append logical entities.

`finish_sketch` consumes the builder and publishes an immutable drawing. It does
not solve constraints or discover regions from intersecting curves. Distinct
contours may overlap in the drawing; their compatibility as a region is checked
when selecting a profile.

`profile(&drawing, .exterior = outline)` uses the selected contour as exterior
and every other declared contour as a hole. Hole winding is handled internally;
callers declare all shapes counterclockwise. Crossings, touching boundaries,
outside holes and nested holes are rejected.

For a drawing shared by several operations, explicitly select only the contours
needed by a profile. The first reference is its exterior; subsequent references
are holes in the supplied order:

```rg
chosen: [2]s.ContourRef = (outline, opening)
section ::= s.profile_from_contours(&drawing, .contours = view(&chosen))!
```

Other contours are ignored, including contours outside the selected region.
An empty selection returns `invalid_region_lengths`; repeated contours are
rejected by geometric admission. Every reference must belong to the drawing.
Both selection paths share geometry assembly, hole reversal and validation.
Neither modifies the drawing or discovers regions from intersecting entities.
Multiple material regions still require the lower-level profile constructor.

The result is an owning `modeling.PlanarProfile`, the same type produced by the
polygonal profile constructors. Its local analytic spans, contour lengths, frame
and tolerance are independent of the drawing's lifetime. The drawing remains
reusable. Sketch contour references are not IDs in the selected profile or a
published model, and do not claim persistent identity across program executions.

For a profile containing only segments, both operations share the same input:

```rg
section ::= drawing | s.profile(&_, .exterior = outline)!
face ::= m.profile_brep(&section)!
model ::= m.extrude(.profile = &section, .displacement = (.x = 0.0, .y = 0.0, .z = 2.0))!
```

`profile_brep` publishes one open planar B-rep face, preserving circular arcs,
endpoint identities and per-use p-curves. `extrude` currently accepts only
segment profiles; a circular or rounded boundary returns `unsupported_boundary`
without consuming the profile. See the [spacer example](../_examples/sketches/spacer_test.rg)
for sketch-to-extrusion usage and the [bearing plate](../_examples/sketches/bearing_plate_test.rg)
for analytic B-rep publication.

Use `m.profile_brep_with_history` when later code needs the face, loop or directed
halfedge produced by a profile region, contour or span. These maps use positions
in the selected profile. To follow a drawing's checked `ContourRef`, retain
selection history as well:

```rg
selection ::= s.profile_with_history(&drawing, .exterior = outline)!
publication ::= m.profile_brep_with_history(&selection.profile)!
image ::= s.profile_contour_image(&selection, .contour = shaft)!
shaft_loop ::= m.published_profile_loop(&publication, .contour = image.contour)!
```

Use `profile_from_contours_with_history` with the same explicit contour list
when a subset needs correspondences. Querying an omitted source contour returns
`not_selected`, distinct from `wrong_domain` and `out_of_bounds`.

`ProfileSelection.profile` owns the selected g. Its optional history
borrows the drawing's domain, so the drawing must remain alive while using the
selection. References from another drawing return `wrong_domain`.

`profile_span_image(&selection, .contour = shaft, .span = i)` maps a local
source span position to a flat selected-profile span position. Its `reversed`
flag means that source parameter `t` corresponds to selected parameter `1-t`.
This accounts for both the reordered exterior and reversed holes. Span positions
outside the source contour return `out_of_bounds`.

History stores one record per drawing contour and resolves spans in constant time,
without a per-span map. Plain `profile` does not allocate this history. Compose
these images with a publication built from `selection.profile`; positions are
not persistent identities or references into an unrelated publication. See
[profile publication](extrusion.md) for the publication contract.

Curved-profile extrusion, constraints and region discovery remain later work.
