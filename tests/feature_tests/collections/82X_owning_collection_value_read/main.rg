read := <.Collection: Type: IndexableValue<.Item: String>> (.items: &Collection) -> () {}

main := (.system: System) -> () {
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&storage
    array ::= unwrap_or_abort(.value = DynamicArray<.t: String>(.capacity = 1))
    read(.items = &array)
}
