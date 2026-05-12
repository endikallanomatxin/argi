AccessMode : CEnum = (
    ..missing,
    ..exists (.code: Int32),
)

main() -> (.status_code: Int32) := {
    status_code = 0
}
