main() -> (.status_code: Int32) := {
    value :: Int32 = 7
    pointer :: ?$&Int32 = ..some(.value = $&value)
    view ::= ArrayView#(.t: Int32)(._data = pointer, ._length = 100000)
    status_code = 0
}
