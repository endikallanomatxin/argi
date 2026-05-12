ImportedStatus : Type = (
    .code: Int32
)

imported_value : Int32 = 0

read_status () -> (.status_code: Int32) := {
    status_code = imported_value
}
