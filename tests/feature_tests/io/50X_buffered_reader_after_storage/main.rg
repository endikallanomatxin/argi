Source: Type = ()

implement Reader<Source> (
    .read_byte = (.self: $&Source) -> (.result: Errable<ReadByte, (..stream_read_failed)>) {
        result = ..ok ..end
    }
)

main := (.system: System) -> () {
    assume allocator := system.page_allocator
    source :: Source = ()
    storage ::= unwrap_or_abort(.value = DynamicArray<UInt8>(.capacity = 1))
    unwrap_or_abort(.value = push($&storage, .value = 0))
    reader ::= BufferedReader(.base = $&source, .buffer = view($&storage))
    deinit($&storage)
    _ ::= Reader<>.read_byte($&reader)
}
