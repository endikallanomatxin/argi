Values : Type = (.wide: Float64)
main() -> (.status_code: Int32 = 0) := {
    narrow :: Float32 = 3.5
    values : Values = (.wide = narrow)
}
