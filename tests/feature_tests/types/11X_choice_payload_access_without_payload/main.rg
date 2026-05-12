Direction : Type = (
    ..north,
    ..south,
)

main () -> (.status_code: Int32) := {
    value : Direction = ..north
    payload := value..north
    status_code = 0
}
