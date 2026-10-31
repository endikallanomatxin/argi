-- Borrowed adapters: no flattening, prefix-sum buffer or per-face allocation.
_EqualIndices := #(.n: UIntNative) (
    .faces : ArrayView#(Array#(.n = n, .t: UIntNative)),
    .count : UIntNative
)

implement#(.n: UIntNative) Indexable#(_EqualIndices#(.n = n)) (
    .Item          : Type = UIntNative
    .length        = (.self: &_EqualIndices#(.n = n)) -> (.count: UIntNative) { count = self&.count }
    .get_reference = (.self: &_EqualIndices#(.n = n), .index: UIntNative) -> (
        .result : Errable#(&UIntNative, (..out_of_bounds))
    ) {
        if n == 0 or index >= self&.count {
            result = ..error(.reason = ..out_of_bounds)
            return
        }
        face ::= get_reference(&self&.faces, .index = index / n)!
        result = ..ok&face&[index % n]
    }
)

implement#(.n: UIntNative) IndexableValue#(_EqualIndices#(.n = n)) (
    .Item : Type = UIntNative
    .get  = (.self: &_EqualIndices#(.n = n), .index: UIntNative) -> (
        .result : Errable#(UIntNative, (..out_of_bounds))
    ) {
        value ::= get_reference(self, .index = index)!
        result = ..ok value&
    }
)

_EqualLengths := (.count: UIntNative, .size: UIntNative)

implement Indexable#(_EqualLengths) (
    .Item          : Type = UIntNative
    .length        = (.self: &_EqualLengths) -> (.count: UIntNative) { count = self&.count }
    .get_reference = (.self: &_EqualLengths, .index: UIntNative) -> (
        .result : Errable#(&UIntNative, (..out_of_bounds))
    ) {
        if index >= self&.count {
            result = ..error(.reason = ..out_of_bounds)
            return
        }
        result = ..ok&self&.size
    }
)

implement IndexableValue#(_EqualLengths) (
    .Item : Type = UIntNative
    .get  = (.self: &_EqualLengths, .index: UIntNative) -> (
        .result : Errable#(UIntNative, (..out_of_bounds))
    ) {
        value ::= get_reference(self, .index = index)!
        result = ..ok value&
    }
)

-- Builds an oriented polyhedral surface, with n vertices in every face.
-- Only the face width is static: the view may have a runtime face count.
from_equal_length_faces := #(
    .Scalar: Type: Float, .vertices_per_face: UIntNative, .Provider: Type: Allocator
) (
    .points         : ArrayView#(g.Point#(Scalar)),
    .faces          : ArrayView#(Array#(.n = vertices_per_face, .t: UIntNative)),
    .tolerance      : Scalar      = 0.000001,
    .allocator      : $&Provider,
    .require_closed : Bool        = true
) -> (.result: Errable#(Model#(Scalar), BuildErrors)) {
    if vertices_per_face < 3 {
        result = ..error(.reason = ..degenerate_face)
        return
    }
    face_count ::= length(&faces).count
    maximum ::= integer_limits(.value = face_count).maximum
    if face_count > maximum / vertices_per_face {
        result = ..error(.reason = ..invalid_face_lengths)
        return
    }
    indices: _EqualIndices#(.n = vertices_per_face) = (
        .faces = faces
        .count = face_count * vertices_per_face
    )
    lengths: _EqualLengths = (.count = face_count, .size = vertices_per_face)
    face_loops: _EqualLengths = (.count = face_count, .size = 1)
    supplied ::= DynamicArray#(g.Plane#(Scalar))(.allocator = allocator)!
    result = _build_faces#(
        .Scalar    : Scalar,
        .Provider  : Provider,
        .Indices   : _EqualIndices#(.n = vertices_per_face),
        .Lengths   : _EqualLengths,
        .FaceLoops : _EqualLengths
    )(
        .points           = points
        .indices          = &indices
        .face_lengths     = &lengths
        .face_loop_counts = &face_loops
        .planar_regions   = false
        .supplied_planes  = &supplied
        .tolerance        = tolerance
        .allocator        = allocator
        .require_closed   = require_closed
    )
}

-- Each length consumes that many consecutive indices. Lengths may be equal.
from_any_length_faces := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .points         : ArrayView#(g.Point#(Scalar)),
    .vertex_indices : ArrayView#(UIntNative),
    .face_lengths   : ArrayView#(UIntNative),
    .tolerance      : Scalar                  = 0.000001,
    .allocator      : $&Provider,
    .require_closed : Bool                    = true
) -> (.result: Errable#(Model#(Scalar), BuildErrors)) {
    face_loops: _EqualLengths = (
        .count = length(&face_lengths).count
        .size  = 1
    )
    supplied ::= DynamicArray#(g.Plane#(Scalar))(.allocator = allocator)!
    result = _build_faces#(
        .Scalar    : Scalar,
        .Provider  : Provider,
        .Indices   : ArrayView#(UIntNative),
        .Lengths   : ArrayView#(UIntNative),
        .FaceLoops : _EqualLengths
    )(
        .points           = points
        .indices          = &vertex_indices
        .face_lengths     = &face_lengths
        .face_loop_counts = &face_loops
        .planar_regions   = false
        .supplied_planes  = &supplied
        .tolerance        = tolerance
        .allocator        = allocator
        .require_closed   = require_closed
    )
}

-- General planar faces: each face starts with an exterior contour, then holes.
from_planar_faces := #(.Scalar: Type: Float, .Provider: Type: Allocator) (
    .points           : ArrayView#(g.Point#(Scalar)),
    .vertex_indices   : ArrayView#(UIntNative),
    .contour_lengths  : ArrayView#(UIntNative),
    .face_loop_counts : ArrayView#(UIntNative),
    .tolerance        : Scalar                  = 0.000001,
    .allocator        : $&Provider,
    .require_closed   : Bool                    = true
) -> (.result: Errable#(Model#(Scalar), BuildErrors)) {
    planes ::= _planar_face_planes(
        .points           = points
        .vertex_indices   = vertex_indices
        .contour_lengths  = contour_lengths
        .face_loop_counts = face_loop_counts
        .tolerance        = tolerance
        .allocator        = allocator
    )!
    built ::= _build_faces#(
        .Scalar    : Scalar,
        .Provider  : Provider,
        .Indices   : ArrayView#(UIntNative),
        .Lengths   : ArrayView#(UIntNative),
        .FaceLoops : ArrayView#(UIntNative)
    )(
        .points           = points
        .indices          = &vertex_indices
        .face_lengths     = &contour_lengths
        .face_loop_counts = &face_loop_counts
        .planar_regions   = true
        .supplied_planes  = &planes
        .tolerance        = tolerance
        .allocator        = allocator
        .require_closed   = require_closed
    )!
    result = ..ok ~built
}
