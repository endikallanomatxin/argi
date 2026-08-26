main() -> (.status_code: Int32) := {
    allocator :: CAllocator = CAllocator()
    allocation ::= allocate(.self = $&allocator, .size = 16)
    data ::= mutable_reinterpret_reference#(.from: UInt8, .to: Int32)(.base = allocation.data).reference
    values ::= array_view#(.t: Int32)(.data = data, .length = 4)

    values[0] = 3
    values[1] = 5
    values[2] = 7
    values[3] = 11

    if values[0] != 3 {
        status_code = 11
        return
    }

    if values[3] != 11 {
        status_code = 12
        return
    }

    status_code = values[1] + values[2]
}
