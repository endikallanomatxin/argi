-- Oriented normal on the face's supporting surface. Like surface_point, this
-- evaluates a chart; it does not classify membership in the trimmed region.
face_normal := #(.Scalar: Type: Float) (
    .model: &Model#(Scalar), .face: FaceId, .u: Scalar, .v: Scalar
) -> (.result: Errable#(g.Displacement#(Scalar), BrepErrors)) {
    info ::= face_info(model, .face = face)!
    normal ::= g.surface_normal(.surface = face_surface(model, .face = face)!, .u = u, .v = v)!
    if info.reversed {
        normal = (0.0 - normal.x, 0.0 - normal.y, 0.0 - normal.z)
    }
    result = ..ok normal
}
