main () -> (.status_code: Int32) := {
    allocator :: DirectAllocator = DirectAllocator()
    original ::= String(.length = 3)
    bytes_set(.string = $&original, .index = 0, .value = 65)
    bytes_set(.string = $&original, .index = 1, .value = 114)
    bytes_set(.string = $&original, .index = 2, .value = 103)

    copied ::= copy(.self = original)
    bytes_set(.string = $&copied, .index = 0, .value = 66)

    original_first ::= bytes_get(.string = &original, .index = 0).byte
    copied_first ::= bytes_get(.string = &copied, .index = 0).byte

    if original_first != 65 {
        status_code = 1
        return
    }

    if copied_first != 66 {
        status_code = 2
        return
    }

    status_code = 0
}
