Backend : Abstract = ()

Concrete : Type = ()
NotBackend : Type = ()

Concrete implements Backend

Wrapper #(.backend_type: Type: Backend) : Type = (
    .backend: $&backend_type
)

main() -> (.status_code: Int32) := {
    value :: NotBackend
    wrapper : Wrapper#(.backend_type: NotBackend) = (.backend = $&value)
    wrapper
    status_code = 0
}
