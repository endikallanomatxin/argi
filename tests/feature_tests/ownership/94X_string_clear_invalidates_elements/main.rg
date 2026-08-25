read(.value: &UInt8) -> () := {}

main(.system: System = System()) -> (.status_code: Int32) := {
    text ::= String(.capacity = 4)
    pointer : &UInt8 = text.allocation.data
    clear(.self = $&text)
    read(.value = pointer)
    deinit(.self = $&text, .allocator = system.allocator)
    status_code = 0
}
