main() -> (.status_code: Int32 = 0) := {
    storage ::= ForeignFunctionInterface()
    memory ::= Memory(.ffi = $&storage)
    moved ::= ~storage
    allocation ::= map_pages(.self = $&memory, .size = 4096, .alignment = 8)
}
