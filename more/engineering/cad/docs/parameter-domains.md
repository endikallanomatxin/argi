# Support parameter domains

`g.surface_parameter_domain(surface).domain` describes the built-in support
chart. It is independent of a face's region and orientation, and does not
validate the support's radius or frame.

Each `ParameterAxis#(Scalar)` is unbounded, periodic with an explicit reference
origin and period, or bounded with explicit lower and upper limits. Bounded
limits can be singular. `SurfaceParameterDomain#(Scalar)` contains the `u` and
`v` axes as small copyable values, without allocation or persistent chart objects.

| Support | u | v | Singularities |
| --- | --- | --- | --- |
| Plane | unbounded | unbounded | none |
| Cylinder | periodic, origin 0, period 2*pi | unbounded axial distance | none |
| Sphere | periodic, origin 0, period 2*pi | latitude [-pi/2, pi/2] | both latitude limits |
| Ring torus | periodic, origin 0, period 2*pi | periodic, origin 0, period 2*pi | none |

A periodic origin is a reference for a fundamental interval, not a topological
seam or a clipping bound. Negative coordinates and coordinates beyond a period
remain valid. The APIs do not normalize them: reducing every point into the
fundamental interval would lose the continuous lift needed for a p-curve that
crosses a period. Periodic equivalents evaluate to the same support within
floating-point error, not necessarily bit-for-bit equality.

`g.validate_surface_parameters(.surface, .u, .v)!` checks finite coordinates and
bounded limits, and returns whether the location is a chart singularity. A
singular boundary collapses the complementary coordinate: at a spherical pole,
longitude no longer distinguishes spatial points. This does not create a
vertex in the model. Singularity checks use represented endpoints exactly;
nearby regular points are not snapped using a modeling tolerance.

`surface_point` validates the support and these chart coordinates. It accepts
spherical poles, rejects latitude outside [-pi/2, pi/2] with `out_of_bounds`, and
preserves unwrapped angles on cylinders and tori. The earlier evaluator allowed
latitude outside that canonical chart through trigonometric continuation;
that behavior is now rejected consistently with face-region queries.
Nonfinite coordinates return `invalid_coordinate`.

`surface_periodicity` remains available as a boolean convenience query derived
from the same descriptors. Face-region queries use the shared coordinate
validation rather than duplicating spherical limits.

These descriptors cover the current analytic charts. They do not express a
multi-chart atlas, transition maps, arbitrary singular sets, or trimmed face
membership. Future support families may need additional chart capabilities;
the topology and p-curve storage do not depend on these descriptors.

See [the domain tests](../geometry/parameter_domain_test.rg) for both scalar
precisions, unwrapped torus evaluation and pole behavior.
