main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    assume writer ::= $&system.terminal&.stdout

    number := format(123) | unwrap_or_abort(_)
    message := concat("Hello world ", &number) | unwrap_or_abort(_)
    unwrap_or_abort(print(&message))
    unwrap_or_abort(print("\n"))

    suffix := concat(&number, "!") | unwrap_or_abort(_)
    unwrap_or_abort(print(&suffix))
    unwrap_or_abort(print("\n"))

    doubled := concat(&number, &number) | unwrap_or_abort(_)
    unwrap_or_abort(print(&doubled))
    unwrap_or_abort(print("\n"))

    literals := concat("left", "right") | unwrap_or_abort(_)
    unwrap_or_abort(print(&literals))
    unwrap_or_abort(print("\n"))

    -- The borrowed result can be consumed within the expression's scope.
    unwrap_or_abort(print(concat("inline ", &number) | unwrap_or_abort(_) | &_))
}
