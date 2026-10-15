Backend#(.Participant: Type): Contract = ()

BackendA : Type = ()
BackendB : Type = ()

implement Backend#(BackendA) ()
implement Backend#(BackendB) ()
Wrapper #(.backend_type: Type: Backend) : Type = (
    .backend: $&backend_type
)

accept_b(.value: Wrapper#(.backend_type: BackendB)) -> (.status_code: Int32) := {
    value
    status_code = 0
}

main() -> (.status_code: Int32) := {
    a :: BackendA
    a_wrapper : Wrapper#(.backend_type: BackendA) = (.backend = $&a)
    status_code = accept_b(.value = a_wrapper)
}
