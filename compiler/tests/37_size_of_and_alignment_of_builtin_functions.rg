-- Exercise builtin size_of and alignment_of using type arguments (type_of helper)

Vector2 : Type = (
    .x: Int32,
    .y: Int16,
)

main () -> (.status_code: Int32) := {
    size_int32 :: Int32 = size_of(.type = Int32)
    if size_int32 != 4 {
        status_code = 1
        return
    }

    align_int32 :: Int32 = alignment_of(.type = Int32)
    if align_int32 != 4 {
        status_code = 2
        return
    }

    v :: Vector2 = (.x = 1, .y = 2)

    size_vec_from_type :: Int32 = size_of(.type = Vector2)
    if size_vec_from_type != 8 {
        status_code = 3
        return
    }

    size_vec_from_value :: Int32 = size_of(.type = type_of(.value = v))
    if size_vec_from_value != 8 {
        status_code = 4
        return
    }

    align_vec :: Int32 = alignment_of(.type = Vector2)
    if align_vec != 4 {
        status_code = 5
        return
    }

    ptr : $&Vector2 = $&v
    size_ptr :: Int32 = size_of(.type = type_of(.value = ptr))
    if size_ptr != 8 {
        status_code = 6
        return
    }

    align_ptr :: Int32 = alignment_of(.type = type_of(.value = ptr))
    if align_ptr != 8 {
        status_code = 7
        return
    }

    status_code = 0
}
