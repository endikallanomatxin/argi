InputStream#(.line: Type) : Abstract = (
    read_line(.self: $&Self) -> (.line: line)
)

OutputStream#(.text: Type) : Abstract = (
    write(.self: $&Self, .text: text) -> ()
    flush(.self: $&Self) -> ()
)
