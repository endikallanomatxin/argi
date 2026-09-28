main (.system: System) -> (.status_code: Int32) := {
    assume allocator ::= $&allocator_storage
    allocated ::= allocate(.self = $&allocator_storage, .size = 4)
    match allocated {
        ..ok ~ payload {
            array :: DynamicArray#(.t: Int32) = (
                ._allocation = ~payload,
                ._length = 100,
                ._capacity = 1,
            )
            status_code = 0
        }
        ..error _ { status_code = 1 }
    }
}
