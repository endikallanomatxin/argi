main(.system: System) -> () := {
    assume allocator := system.page_allocator
    queue ::= unwrap_or_abort(.value = Deque#(.t: Int32)())
    copy ::= queue
    length(.self = &copy)
}
