write := (.slot: $&Int32) -> () { slot& = 42 }


main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    array ::= unwrap_or_abort(DynamicArray#(Int32)(.capacity = 1, .allocator = system.page_allocator))
    push_assume_capacity#(Int32)(.self = $&array, .value = 0)
    slot ::= unwrap_or_abort(get_mutable_reference(.self = $&array, .index = 0))
    task ::= unwrap_or_abort(async#(write)(.args = (.slot = slot), .executor = executor))
    _ = unwrap_or_abort(await($&task))
    result ::= unwrap_or_abort(get_reference(.self = &array, .index = 0))
    if result& != 42 { abort }
}
