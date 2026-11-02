# Toroidal latitude bands

The ordinary B-rep builder admits a ring-torus face between two latitude
contours. Each contour shares one circular or elliptic support and may be a
closed edge or a sequence of proper arcs. No longitudinal seam is required.

Each use has a linear p-curve with canonical longitude increasing by the
edge interval in turns, and constant tube angle. Supply the lower contour
first and the upper second, with opposite traversal senses relative to face
orientation. The upper tube angle exceeds the lower by less than one turn.
For example, `[5.5, 7.0]` crosses the tube-angle period without splitting a face.

Admission compares all 3D curve coefficients against the torus support,
validates complete contour coverage and requires resolved geometric separation
of the boundaries. The same model arrays, interval pool and topology writer
are used for planes, cylinders and toroidal bands.

`face_contains_parameters` reduces the tube angle periodically; longitude is
unrestricted by this band. Canonical interval points include their boundaries.
Reduction near a boundary can be numerically ambiguous, especially at large
unwrapped angles; such queries return `numerical_ambiguity` rather than guessing.
Orientation reversal retains the selected region. Paired incidence still does
not certify a solid.

This is an admitted analytic trim family, not arbitrary torus trimming.
Meridional, diagonal and mixed-support contour admission remain unsupported.
