# CAD

An experimental geometric modeling kernel written in Argi.

Build and inspect immutable polyhedral surfaces with planar faces and holes,
scalar-generic geometry, nominal entity IDs and allocation-free boundary traversal.
Extrude concave profiles with holes and disconnected regions, using `Float32` or `Float64`.
Represent cylinders, spheres and tori without artificial seam edges.

The kernel is bundled as an Argi library under `more/engineering/cad`. See the [runnable examples](_examples/README.md)
for constructing and traversing models.

- [Usage and construction contracts](docs/usage.md)
- [Sketch builder](docs/sketches.md)
- [Periodic surfaces](docs/periodic-surfaces.md)
- [Support parameter domains](docs/parameter-domains.md)
- [Analytic trimming foundation](docs/analytic-trimming.md)
- [Circular arcs and planar regions](docs/circular-regions.md)
- [Mixed parametric contours](docs/parametric-regions.md)
- [Oblique cylindrical trims](docs/cylinder-trimming.md)
- [Toroidal latitude bands](docs/toroidal-trimming.md)
- [Orientation and region](docs/orientation.md)
- [Surface and face normals](docs/surface-normals.md)
- [Differential geometry](docs/differential_geometry.md)
- [Domains and incremental construction](docs/model-builder.md)
- [Merging adjacent coplanar faces](docs/face-merging.md)
- [Splitting a planar face](docs/face-splitting.md)
- [Connecting an exterior to a hole](docs/face-bridging.md)
- [Extrusion](docs/extrusion.md)
- [Performance measurements](docs/benchmarks.md)
- [Architecture and computational costs](docs/architecture.md)
- [Development and testing](docs/development.md)

Early stage: boolean operations and arbitrary curved trimming are not implemented.
Build the compiler and its bundled libraries from this repository; see the development guide.
