-- Shared fixture for the advanced editing examples.
-- Face 0 is the planar top annulus. Four outer sides meet at z=-2;
-- four pocket sides meet at z=-1. Both boundaries share that same top face.
_closed_pocket := (.allocator: $&Virtual#(Allocator)) -> (
    .result : Errable#(t.Model#(Float64), t.BuildErrors)
) {
    points: [10]g.Point#(Float64) = (
        (0.0, 0.0, 0.0),
        (4.0, 0.0, 0.0),
        (4.0, 4.0, 0.0),
        (0.0, 4.0, 0.0),
        (1.0, 1.0, 0.0),
        (1.0, 3.0, 0.0),
        (3.0, 3.0, 0.0),
        (3.0, 1.0, 0.0),
        (2.0, 2.0, -2.0),
        (2.0, 2.0, -1.0)
    )
    -- An outer pyramid with an open pyramidal pocket. Its planar top has a hole.
    vertices: [32]UIntNative = (
        0, 1, 2, 3, 4, 5, 6, 7, 1, 0, 8, 2, 1, 8, 3, 2, 8, 0, 3, 8, 5, 4, 9, 6, 5, 9, 7, 6, 9,
        4, 7, 9
    )
    lengths: [10]UIntNative = (4, 4, 3, 3, 3, 3, 3, 3, 3, 3)
    face_loops: [9]UIntNative = (2, 1, 1, 1, 1, 1, 1, 1, 1)
    model ::= t.from_planar_faces(
        .points           = view(&points)
        .vertex_indices   = view(&vertices)
        .contour_lengths  = view(&lengths)
        .face_loop_counts = view(&face_loops)
        .allocator        = allocator
    )!
    result = ..ok ~model
}
