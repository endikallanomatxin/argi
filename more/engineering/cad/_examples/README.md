# Runnable examples

Each `_test.rg` file demonstrates one use of the public API. Read the short
introduction, follow the construction, then inspect the assertions showing the
expected result. Imports in each directory's `imports.rg` are shared by all
files in that module: `t` is topology, `g` geometry, `m` modeling and
`s` the sketch builder.

Commands below run from the repository root after `zig build`.

## 1. Construct and traverse a model

- [Tetrahedron](construction/tetrahedron_test.rg): start here; triangular faces,
  inferred types, closure and allocation-free boundary traversal.
- [Quad cube](construction/quad_cube_test.rg): the same API with quads and Float32.
- [Mixed face lengths](construction/mixed_face_lengths_test.rg): a pyramid with
  a quad base and triangular sides, supplied as indices and lengths.
- [Incremental triangle](construction/incremental_triangle_test.rg): declare
  vertices, edges and a face, then publish the model and resolve its handles.

```sh
./zig-out/bin/argi test more/engineering/cad/_examples/construction --filter usage_
```

## 2. Declare a sketch and select a profile

- [Bearing mounting plate](sketches/bearing_plate_test.rg): a dimensioned recipe
  for a rounded plate with a shaft opening and two symmetric mounting holes.
  Named dimensions describe the shaft opening and mounting geometry; one spacing
  controls both mounting holes. Retained exterior and shaft references select
  the profile and locate the shaft loop in the published planar B-rep face.
- [Rectangular spacer](sketches/spacer_test.rg): select a rectangle with a
  rectangular opening, leave another contour unused, then follow the opening's
  reference to its walls after oblique extrusion.
- [Sketch on a generated cap](sketches/stacked_sketches_test.rg): follow an
  extrusion cap, choose its origin and heading, and build another sketch and
  extrusion on its plane. The two models remain separate.
- [Reuse a profile](sketches/reused_profile_test.rg): declare one cross-section,
  place copies on two work frames, and follow the original opening reference
  to the walls generated at each placement.
- [Boundary work frame](sketches/boundary_work_frame_test.rg): recover a circular
  opening's directed derivative and face normal, then orient another sketch at
  a point on that analytic boundary.

```sh
./zig-out/bin/argi test more/engineering/cad/_examples/sketches --filter usage_
```

## 3. Extrude a profile

- [Oblique prism](extrusion/prism_test.rg): validate one contour and extrude it.
- [Disconnected regions](extrusion/disconnected_regions_test.rg): group contours
  into regions and extrude several components together.

```sh
./zig-out/bin/argi test more/engineering/cad/_examples/extrusion --filter usage_
```

## 4. Use an analytic surface

- [Seamless torus](surfaces/seamless_torus_test.rg): a complete periodic support
  represented by a face without boundary loops or artificial seam edges.

```sh
./zig-out/bin/argi test more/engineering/cad/_examples/surfaces --filter usage_
```

## 5. Edit faces and follow correspondences

- [Merge](face_editing/merge_faces_test.rg): join coplanar triangles and map an
  original face into the result.
- [Split](face_editing/split_face_test.rg): cut a square at two edge parameters
  and inspect both resulting faces.
- [Split with a hole](face_editing/split_face_with_hole_test.rg): retain the hole
  while splitting a face in a closed shell.
- [Bridge a hole](face_editing/bridge_hole_test.rg): connect two boundary loops
  with an edge traversed twice in opposite directions.
- [Compose operations](face_editing/compose_operations_test.rg): bridge, split
  and merge while preserving the internal connection.

The last three examples share [pocket.rg](face_editing/pocket.rg). Its top face
has a square hole; the surrounding faces form a closed shell. The fixture is
separate so the examples can focus on the operation being taught.

```sh
./zig-out/bin/argi test more/engineering/cad/_examples/face_editing --filter usage_
```

To run just one example, select its test name, for example:

```sh
./zig-out/bin/argi test more/engineering/cad/_examples/construction --filter usage_closed_tetrahedron
```

Run these module commands individually. The `usage_` filter selects the public
examples rather than tests discovered in imported library modules. For compiler
memory limits and broader verification, see [development](../docs/development.md).
