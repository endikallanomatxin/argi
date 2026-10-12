main := (.system: System) -> () {
    deallocate(
        .self      = system.page_allocator
        .data      = raw_pointer#(UInt8)(.address = 0)
        .size      = 0
        .alignment = 1
    )
}
