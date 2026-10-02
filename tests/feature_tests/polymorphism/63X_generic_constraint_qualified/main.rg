library ::= import("./library")
main() -> (.status_code: Int32 = 0) := {
    value :: library.Owned = (.value = 7)
    library.accept(.value = &value)
}
