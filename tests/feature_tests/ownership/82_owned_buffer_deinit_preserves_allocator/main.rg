main(.system: System = System()) -> (.status_code: Int32) := {
    text :: String = String(.allocator = system.allocator, .capacity = 8)
    deinit(.self = $&text, .allocator = system.allocator)

    second :: String = String(.allocator = system.allocator, .capacity = 8)
    deinit(.self = $&second, .allocator = system.allocator)
    status_code = 0
}
