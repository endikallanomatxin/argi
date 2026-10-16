Owner: Type = (.value: Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {}
)

Policy: Type = ()

implement OrderPolicy#(Policy, Owner) (
    .less = (.self: &Policy, .left: &Owner, .right: &Owner) -> (.ok: Bool) {
        ok = left&.value < right&.value
    }
)

run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    policy ::= Policy()
    queue ::= PriorityQueue#(.t: Owner)(.order = &policy)!
    push($&queue, .value = Owner(.value = 1))!
    copied ::= peek(&queue).value
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
