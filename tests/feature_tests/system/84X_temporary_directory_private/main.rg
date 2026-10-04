main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    owner ::= TemporaryDirectory(.self = system.file_sys, .parent = ".")!
    _ ::= owner._handle
}
