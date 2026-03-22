sum_iterable(.items: &Iterable#(.t: Int32)) -> (.sum: Int32) := {
    iterator ::= to_iterator(.value = items)
    sum = 0

    while has_next(.self = &iterator) {
        value :: Int32 = next(.self = $&iterator)
        sum = sum + value
    }
}

main () -> (.status_code: Int32) := {
    allocator :: DirectAllocator = DirectAllocator()
    values : Array#(.n = 3, .t: Int32) = (3, 4, 5)
    array_sum :: Int32 = sum_iterable(.items = &values).sum

    dyn :: DynamicArray#(.t: Int32) = DynamicArray#(.t: Int32)(.capacity = 2)
    dyn | push(.self = $&_, .value = 2)
    dyn | push(.self = $&_, .value = 6)
    dynamic_sum :: Int32 = sum_iterable(.items = &dyn).sum

    if array_sum != 12 {
        status_code = 1
        return
    }

    if dynamic_sum != 8 {
        status_code = 2
        return
    }

    status_code = 0
}
