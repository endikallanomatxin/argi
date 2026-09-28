unsafe_allocation := #import("../../_support/unsafe_allocation")
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.allocator

    i :: UIntNative = 0
    while i < 2 {
        local ::= String(.allocator = system.allocator, .capacity = 1)
        pushed ::= push_byte(.self = $&local, .byte = 65, .allocator = system.allocator)
        if is(.value = pushed, .variant = ..error) {
            status_code = 1
            return
        }
        data ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&local.allocation, .offset = 0).reference
        if data& != 65 {
            status_code = 2
            return
        }
        deinit(.self = $&local, .allocator = system.allocator)
        i = i + 1
    }
}
