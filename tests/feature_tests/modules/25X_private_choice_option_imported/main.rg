dep := import ("./dep")

Visible := (
    dep .._hidden_reason
)

main := () -> (.status_code: Int32) {
    status_code = 0
}
