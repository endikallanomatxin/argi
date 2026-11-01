-- Validate geometry before allocating the model's connectivity buffers.
_planar_face_planes := #(.Scalar: Type: Float) (
    .points           : ArrayView#(g.Point#(Scalar)),
    .vertex_indices   : ArrayView#(UIntNative),
    .contour_lengths  : ArrayView#(UIntNative),
    .face_loop_counts : ArrayView#(UIntNative),
    .tolerance        : Scalar,
    .allocator        : $&Virtual#(Allocator)
) -> (.result: Errable#(DynamicArray#(g.Plane#(Scalar)), BuildErrors)) {

    halfedges ::= length(&vertex_indices).count
    loops ::= length(&contour_lengths).count
    faces ::= length(&face_loop_counts).count
    boundary ::= DynamicArray#(g.Point#(Scalar))(.allocator = allocator, .capacity = halfedges)!
    planes ::= DynamicArray#(g.Plane#(Scalar))(.allocator = allocator, .capacity = faces)!
    i :: UIntNative = 0
    while i < halfedges {
        index ::= get(&vertex_indices, .index = i)!
        push($&boundary, .value = get(&points, .index = index)!, .allocator = allocator)!
        i = i + 1
    }
    boundary_view ::= view(&boundary)
    loop :: UIntNative = 0
    cursor :: UIntNative = 0
    f :: UIntNative = 0
    while f < faces {
        n ::= get(&face_loop_counts, .index = f)!
        if n == 0 or n > loops - loop {
            result = ..error(.reason = ..invalid_region_lengths)
            return
        }
        start ::= cursor
        first ::= loop
        end ::= loop + n
        while loop < end {
            count ::= get(&contour_lengths, .index = loop)!
            if count > halfedges - cursor {
                result = ..error(.reason = ..invalid_face_lengths)
                return
            }
            cursor = cursor + count
            loop = loop + 1
        }
        lengths: [1]UIntNative = (n)
        region_view ::= view(&lengths)
        contour_view ::= slice(&contour_lengths, .start = first, .count = n)!
        point_view ::= slice(&boundary_view, .start = start, .count = cursor - start)!
        plane ::= g.planar_regions_plane#(.Scalar: Scalar)(
            .points              = point_view
            .contour_lengths     = contour_view
            .region_lengths      = region_view
            .tolerance           = tolerance
            .allocator           = allocator
            .require_orientation = true
        )!
        push($&planes, .value = plane, .allocator = allocator)!
        f = f + 1
    }
    if loop != loops or cursor != halfedges {
        result = ..error(.reason = ..invalid_face_lengths)
        return
    }
    result = ..ok ~planes
}
