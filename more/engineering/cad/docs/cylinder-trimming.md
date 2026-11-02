# Cylindrical bands with oblique boundaries

The ordinary B-rep builder can construct a cylindrical band between two planar
sections, with optional planar caps sharing its boundary edges. No seam edge,
polygonization or cylinder-specific model constructor is needed.

## Geometric primitives

`g.Ellipse#(Scalar)` stores a center and two independent conjugate radius vectors:

```
P(angle) = center + cosine * cos(angle) + sine * sin(angle)
```

The vectors need not be principal or orthogonal axes. This preserves the
natural angular parameter of a section of a cylinder. `g.ellipse_point` validates
finite, nondegenerate support data and evaluates the curve. `t.Curve` adds an
ellipse alternative; published payloads live in a typed ellipse pool, with the
same descriptor IDs and interval IDs used for other edge curves.

`PCurve.harmonic` describes a linear plus trigonometric chart curve:

```
UV(angle) = origin + linear * angle + cosine * cos(angle) + sine * sin(angle)
```

`start` and `end` are angles in radians; halfedge evaluation maps its normalized
parameter to that interval. Traversal reversal changes this mapping, leaving
the canonical coefficients unchanged. This representation is independent of
which support eventually admits the p-curve.

## Admission

A cylindrical band takes two full-period contours via
`declare_trimmed_face(.boundaries, .contour_lengths)`. The first is the lower
section and the second the upper. Each contour may be one vertexless edge or
a connected sequence of circular or elliptic arcs sharing one support.
Their harmonic p-curves have:

```
u = angle
v = height + cosine_height * cos(angle) + sine_height * sin(angle)
```

The coefficient certificate compares the complete 3D curve with its cylindrical
image. It then proves a conservative positive gap between the two height
functions using their constant difference and harmonic amplitude. Crossing
boundaries are rejected; near contact returns `numerical_ambiguity`. This uses
floating-point arithmetic and modeling tolerance, not exact predicates.

The same ellipse edge can be used on a planar cap with its own elliptical
p-curve. Admission on a plane likewise compares center and radius-vector
coefficients and checks orientation. Planar ellipse admission currently covers
one complete contour without holes, optionally partitioned into proper ellipse
arcs with explicitly shared endpoint vertices. Different supports within one
contour, ellipse holes and arbitrary mixed-curve regions remain unsupported.

## Topology and queries

An obliquely capped cylinder has three faces, two edges, four loops and four
halfedges, with no vertices or longitudinal seam. Both faces incident to an
edge share its canonical curve and interval. `is_closed` reports paired
incidence; it remains distinct from a general solid certificate.

`face_contains_parameters` checks the cylindrical region between its admitted
height functions or the planar cap disk in its parameter chart. Angles remain
unwrapped. Orientation reversal preserves region, geometric sharing and numeric
entity IDs. Legacy periodic constructors remain available; their older trims
do not acquire p-curves implicitly.

See [the construction tests](../topology/cylinder_trimming_test.rg) for both
scalar precisions, rejection cases and shared-boundary evaluation on all faces.
The [partitioned-contour tests](../topology/periodic_contours_test.rg) also compare
the same regions after splitting the boundary into unequal arcs across a period.
The partitioned shell has four vertices, four edges and eight halfedges, with
the same three faces and two curve supports; no chart seam is introduced.

Contour admission scans each use once, without an auxiliary allocation. It
checks common support identity, consistent traversal, integer phase continuity
and exactly one covered turn. Every use is then checked against its surface.
Canonical parameter checks remain exact; alternative encodings that cannot
meet this contract return `unsupported_parameterization`.
