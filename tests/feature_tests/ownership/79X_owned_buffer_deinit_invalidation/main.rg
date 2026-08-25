read(.value: &UInt8) -> () := {}

main(.system: System = System()) -> (.status_code: Int32) := {
    text :: String = String(.allocator = system.allocator, .capacity = 8)
    pointer : &UInt8 = text.allocation.data
    deinit(.self = $&text, .allocator = system.allocator)
    read(.value = pointer)
    status_code = 0
}
