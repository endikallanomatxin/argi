# Surface and face normals

`g.surface_normal(.surface, .u, .v)` returns a unit `Displacement` in world
coordinates. At regular parameters its direction agrees with `du × dv`.
It validates the support and its parameter domain, using the same errors as
`surface_point`.

Planes normalize their supplied normal. Cylinders, spheres and ring tori use
analytic formulas in their validated right-handed frames. Evaluation does not
subtract world points or multiply by radii, avoiding cancellation from large
translations and derivative overflow or underflow at extreme radii.

At a spherical pole, the chart is singular but the smooth surface has a unique
normal. Evaluation returns the signed frame axis exactly, independently of
longitude. This guarantee applies to the supported analytic families; it does
not claim that every singular parametrization has a defined normal.

`t.face_normal(.model, .face, .u, .v)` applies `Face.reversed` to the support
normal. Reversing a model therefore negates the face normals while retaining
its supports, parameter charts and trimmed regions. Normals describe the
orientation of the shell, not a certificate that it bounds a valid solid.

Both queries evaluate the supporting chart without testing trimmed membership.
Use `face_contains_parameters` separately where the admitted region classifier
is available. No cache, persistent normal array or allocation is required.

Tests cover rotated frames, both scalar precisions, chart secants, periods,
spherical poles, radius scaling, invalid parameters and shell reversal.
