dep := #import("./dep")

Visible : Type = (
    dep.._hidden_reason
)

main() -> (.status_code: Int32) := {
    status_code = 0
}
