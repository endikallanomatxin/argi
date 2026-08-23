read(.value: &UInt8) -> () := {}

main(.system: System = System()) -> (.status_code: Int32) := {
    text ::= String(.capacity = 1)
    push_byte(.self = $$&text, .byte = 1, .allocator = system.allocator)
    pointer : &UInt8 = text.allocation.data
    push_byte(.self = $$&text, .byte = 2, .allocator = system.allocator)
    read(.value = pointer)
    deinit(.self = $$&text, .allocator = system.allocator)
    status_code = 0
}
