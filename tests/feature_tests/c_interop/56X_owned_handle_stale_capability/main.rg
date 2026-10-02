owned := import("../../_support/owned_foreign_handle")
main() -> (.status_code: Int32 = 0) := {
    capability ::= ForeignFunctionInterface()
    assume ffi := $&capability
    handle ::= unwrap_or_abort(.value = owned.OwnedHandle(.value = 42))
    moved ::= ~capability
    status_code = owned.read(.self = &handle)
}
