read(.items: &IndexableValue#(.t: String)) -> () := {}
main(.system: System) -> () := {
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&storage
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: String)(.capacity = 1))
    read(.items = &array)
}
