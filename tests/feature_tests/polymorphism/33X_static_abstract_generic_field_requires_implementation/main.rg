Backend#(.Participant: Type): Contract = ()

Concrete: Type = ()

NotBackend: Type = ()

implement Backend#(Concrete) ()

Wrapper := #(.backend_type: Type: Backend) (
    .backend : $&backend_type
)

main := () -> (.status_code: Int32) {
    value :: NotBackend
    wrapper: Wrapper#(.backend_type: NotBackend) = (.backend = $&value)
    wrapper
    status_code = 0
}
