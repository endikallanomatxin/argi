main := () -> (.status_code: Int32 = 0) {
    assume ffi ::= $&ForeignFunctionInterface()
    allocator_storage ::= CAllocator(.ffi = ffi)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator

    inner ::= unwrap_or_abort(.value = HashMap#(.key: String, .value: String)())
    key ::= unwrap_or_abort(.value = format(.value = "key"))
    value ::= unwrap_or_abort(.value = format(.value = "value"))
    unwrap_or_abort(.value = put($&inner, .key = ~key, .value = ~value))

    outer ::= unwrap_or_abort(
        .value = HashMap#(.key: Int32, .value: HashMap#(.key: String, .value: String))()
    )
    unwrap_or_abort(.value = put($&outer, .key = 7, .value = ~inner))
    copied ::= unwrap_or_abort(.value = copy(&outer, .allocator = allocator))
    deinit($&outer)

    match get_reference(&copied, .key = &7).result {
        ..none { abort }
        ..some found {
            match get_reference(found.value, .key = "key").result {
                ..none { abort }
                ..some text { if view(text.value) != "value" { abort } }
            }
        }
    }
}
