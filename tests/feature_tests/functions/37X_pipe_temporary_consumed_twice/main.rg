Owner : Type = (.value: Int32)
Owner deinit(.self: $&Owner) -> () := {}
produce() -> (.value: Owner) := { value = Owner(.value = 7) }
consume(.first: Owner, .second: Owner) -> () := {}
main() -> (.status_code: Int32 = 0) := {
    [produce() | consume(.first = _, .second = _)]
}
