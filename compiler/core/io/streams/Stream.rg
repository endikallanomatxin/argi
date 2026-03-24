InputStream#(.line: Type) : Abstract = (
    read_line(
        .self: $&Self,
        .allocator: $&Allocator = #reach allocator, system.allocator,
    ) -> (.line: line)
)

OutputStream#(.text: Type) : Abstract = (
    write(.self: $&Self, .text: text) -> ()
    flush(.self: $&Self) -> ()
)
