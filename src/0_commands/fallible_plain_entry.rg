-- Reporting is checked language code and finishes before entry resources drop.
__argi_entry() -> (.status_code: Int32 = 0) := {
    __ARGI_TRACER_SETUP__
    ffi_storage ::= ForeignFunctionInterface()
    assume ffi ::= $&ffi_storage
    terminal_storage ::= Terminal()
    terminal ::= $&terminal_storage
    __ARGI_CALL__
}
