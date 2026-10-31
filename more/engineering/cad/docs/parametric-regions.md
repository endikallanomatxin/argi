# Mixed parametric contours

`g.ContourSpan` describes a directed 2D segment or circular arc with start,
end, center and signed sweep in radians. Sweep zero denotes a segment. These
are transient geometric data, independent of B-rep IDs, surfaces and incidence.

`g.validate_contour_region(.spans, .lengths, .tolerance, .reversed)` admits one
exterior followed by holes. It checks finite and nondegenerate spans, endpoint
continuity, intersections, orientation and hole nesting. Signed area integrates
arcs analytically. Line/line, line/circle and circle/circle intersections use
analytic constructions; admission does not polygonize a curve.

`g.locate_in_contour_spans` classifies a point against an admitted contour as
inside, outside or boundary. Ray parity uses analytic circular intersections,
half-open endpoint rules and zero contribution from tangencies. The query can
also accumulate contributions from individual admitted spans without allocating.

Admission uses quadratic pair checks and no auxiliary allocation. Coordinate
range and precision checks reject unsupported arithmetic; these floating-point
constructions are not exact predicates or a general robust arrangement engine.
Contacts beyond adjacent shared endpoints are rejected. Unsupported or ambiguous
near-parallel and near-tangent constructions may return `numerical_ambiguity`.

## B-rep integration

A planar B-rep face may mix segment supports and circular supports in the same
contour, with circular or mixed holes. `declare_edge` accepts segment subintervals
within `[0, 1]`, including a complete segment, and proper circular intervals.
Endpoint handles remain explicit identities.

Before region admission, each p-curve is checked against its 3D edge and plane.
Affine segments use endpoint correspondence; circular arcs use coefficient
correspondence. Conversion to chart spans then feeds the surface-independent
region validator. Topological continuity remains a separate check on vertex IDs.

One temporary contiguous span array is allocated during admission. Published
models retain their original typed supports, intervals, p-curves and connectivity;
there is no second stored region representation. Membership reconstructs span
values during traversal without allocating. Inversion changes traversal and face
orientation together, preserving the region.

The same path is selected for planar faces bounded by segments and circular arcs,
including contours made entirely of arcs or vertexless full circles. Arcs in one
contour may use different circle supports. Membership includes the modeling-
tolerance band around exterior and hole boundaries, consistently with the chart
classifier. Genuine elliptic contours retain their separate analytic certificate.
Mixed ellipses and arbitrary p-curves are not yet admitted by the span validator.
See [construction tests](../topology/planar_contour_trimming_test.rg).
