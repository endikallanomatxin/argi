sum_iterator(.it: $&Iterator#(.t: Int32)) -> (.sum: Int32) := {
    sum = 0
    while has_next(.self = it) {
        value :: Int32 = next(.self = it)
        sum = sum + value
    }
}

main () -> (.status_code: Int32) := {
    values : Array#(.n = 3, .t: Int32) = (2, 4, 6)
    array_it ::= to_iterator(.value = &values)
    array_sum :: Int32 = sum_iterator(.it = $&array_it).sum

    dyn :: DynamicArray#(.t: Int32) = DynamicArray#(.t: Int32)(.capacity = 2)
    dyn | push(.self = $&_, .value = 5)
    dyn | push(.self = $&_, .value = 7)
    dynamic_it ::= to_iterator(.value = &dyn)
    dynamic_sum :: Int32 = sum_iterator(.it = $&dynamic_it).sum

    if array_sum != 12 {
        status_code = 1
        return
    }

    if dynamic_sum != 12 {
        status_code = 2
        return
    }

    status_code = 0
}
