main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()

    allocator_storage ::= CAllocator(.ffi = ffi)
    assume allocator ::= $&allocator_storage
    first :: (.text: String = unwrap_or_abort(.value = String(.length = 3))) = ()
    second :: (.text: String = unwrap_or_abort(.value = String(.length = 3))) = ()
    deinit(.self = $&first.text)
    if byte_length(.self = &second.text).count != 3 { abort }
    status_code = 42
}
