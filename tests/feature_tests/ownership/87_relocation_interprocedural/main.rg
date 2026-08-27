move_between#(.t: Type)(.source: $&t, .destination: $&t) -> () := {
    relocate(.source = source, .destination = destination)
}

main(.system: System = System()) -> (.status_code: Int32) := {
    result ::= allocate(.self = system.allocator, .size = 1)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            source ::= ~payload
            destination :: Allocation
            move_between(.source = $&source, .destination = $&destination)
            deinit(.self = $&destination)
            status_code = 0
        }
    }
}
