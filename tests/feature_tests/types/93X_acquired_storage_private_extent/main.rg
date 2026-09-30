main(.system: System) -> (.status_code: Int32 = 0) := {
    storage ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    storage._size = 1000000
}
