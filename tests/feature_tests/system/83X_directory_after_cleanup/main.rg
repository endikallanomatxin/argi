main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    directory ::= Directory(.self = system.file_sys, .path = ".")!
    deinit(.self = $&directory)
    _ ::= next(.self = $&directory)
}
