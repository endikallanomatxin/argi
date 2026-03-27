Touched : Abstract = (
    touch(
        .self: $&Self,
        .allocator: $&Allocator = #reach allocator, system.allocator,
    ) -> ()
)

Thing : Type = (
    .marker: Int32 = 0
)

touch(
    .self: $&Thing,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> () := {
    allocator2 ::= allocator
    _ ::= allocator2
}

Thing implements Touched

main(.system: System = System()) -> (.status_code: Int32) := {
    thing :: Thing = (
        .marker = 0
    )
    touch(.self = $&thing)
    status_code = 0
}
