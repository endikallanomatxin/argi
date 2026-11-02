# Differential geometry

Differential queries evaluate the existing analytic supports without creating
entities, changing model storage or allocating scratch. Derivatives retain their
magnitude: they are not normalized tangents. Coordinates and distance tolerances
use model units; angular parameters use radians unless stated otherwise.

`g.surface_derivatives(.surface = support, .u = u, .v = v)` returns
`SurfaceDerivatives` containing `du`, `dv` and `singular`. The derivatives use the
same chart as `surface_point`: plane coordinates are lengths, cylinder `u` is
longitude and `v` axial distance, sphere `u` is longitude and `v` latitude, and
torus coordinates are its two angles. Periodic parameters remain unwrapped.

At sphere poles, `singular` is true and `du` is exactly zero. `dv` is the
one-sided latitude derivative at the selected longitude; it still depends on
longitude at a pole. Nearby regular points are not snapped to singularities.
Use `surface_normal` for the continued support normal at poles; normalizing
`du cross dv` there is undefined. At regular points this cross product agrees
with the support normal. Face orientation does not change support derivatives.

Support and parameter validation match point evaluation. Nonfinite inputs,
invalid surfaces, parameters outside bounded domains and nonfinite results
return the corresponding geometry errors. Derivatives do not include frame
translation, avoiding cancellation from subtracting translated point samples.
These first-order queries do not certify conditioning, exactness or intersection
convergence. Second derivatives and curvature are separate future capabilities.

The [boundary work-frame example](../_examples/sketches/boundary_work_frame_test.rg)
composes sketch references, publication history, directed derivatives and face
normals to place another sketch. The derivative supplies the heading; explicit
normalization belongs to frame construction. A different parameterization can
change derivative speed while preserving this heading.

`circle_derivative(.circle = circle, .angle = angle)` and
`ellipse_derivative(.ellipse = ellipse, .angle = angle)` differentiate with
respect to radians. Circle speed equals its radius; conjugate ellipse axes
need not be principal axes. Point and derivative evaluation share support
validation. Ellipse independence is tested using normalized axes, avoiding
spurious degeneracy or overflow from squaring the model-unit scale. This is
not a certificate of numerical conditioning for nearly dependent axes.

`topology.curve_derivative(.curve = support, .parameter = t)` uses the same
normalized `[0,1]` parameter as `curve_point`. For circular and elliptic supports
it includes the full-turn factor `2*pi` relative to the angular derivative.
For a segment the derivative is `end-start`.

`halfedge_derivative(&model, .halfedge = use, .parameter = t)` differentiates
with respect to that directed use's own `[0,1]` parameter. It includes the edge
interval width and a negative sign for reversed uses. Periodic edge intervals
can cross a fundamental period, while the public use parameter stays bounded.
Under model orientation reversal, the derivative at `t` becomes the negative
of the original derivative at `1-t`. IDs, curves and canonical intervals remain
unchanged by that orientation operation. Neither derivative query normalizes
its output or adds the surface's normal orientation.

`pcurve_derivative(.curve = trim, .parameter = t)` returns a typed
`ParameterDerivative` with `u` and `v` rates. It differentiates the normalized
p-curve parameter, including the angular interval factor for harmonic/elliptic
p-curves. Linear terms of harmonic curves are included. Decreasing angular
intervals and stationary curves can be evaluated; admission decides whether
they describe a permissible topological boundary.

`halfedge_parameter_derivative(&model, .halfedge = use, .parameter = t)` returns
those chart rates along the directed use. It reverses both the evaluation
parameter and derivative sign when needed. P-curves already encode their edge
interval; this query does not multiply by that interval a second time. Uses
without p-curves return `unsupported_boundary`, matching `halfedge_parameters`.
Point and derivative queries validate every p-curve coefficient as finite.

For a represented boundary, the first-order consistency property is
`halfedge_derivative(t) = surface.du * uv_derivative.u + surface.dv * uv_derivative.v`.
Use the support and parameters of that halfedge's own face. Different uses of
one shared 3D edge may have different p-curves, charts and traversal directions.

The colocated property tests exercise the same chain rule on mixed planar
contours, a shared spherical/planar circular boundary, partitioned oblique
cylinder boundaries and toroidal bands crossing periodic coordinates. They
cover both scalar precisions, opposite uses and full orientation reversal.
A segment supported on a larger segment also checks the distinct interval
factors explicitly. These are regression properties for represented analytic
families, not a proof for arbitrary future surface or curve implementations.
