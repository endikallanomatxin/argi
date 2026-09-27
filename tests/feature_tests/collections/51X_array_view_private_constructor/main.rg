main() -> (.status_code: Int32) := {
    value :: Int32 = 7
    view ::= ArrayView#(.t: Int32)(._data = $&value, ._length = 100000)
    status_code = 0
}
