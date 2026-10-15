python := import ("python")
make(.ffi: $&ForeignFunctionInterface) -> (.result: python.Object) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = ffi)).result
    object ::= unwrap_or_abort(.value = python.none(.self = &interpreter)).result
    result = ~object
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    object ::= make(.ffi = system.ffi).result
    python.is_none(.self = &object)
}
