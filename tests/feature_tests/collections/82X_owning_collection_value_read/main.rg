read := #(.Collection: Type: IndexableValue#(.Item: String)) (.items: &Collection) -> () {}

main := (.system: System) -> () {

    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator_concrete := $&storage
    virtual_allocator ::= to_virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: String)(.capacity = 1))
    read(.items = &array)
}
