main() -> (.status_code: Int32 = 0) := {
    values :: [0]UInt8 = ()
    borrowed_view ::= view(.self = $&values)
    pointer ::= data(.self = &borrowed_view).pointer
}
