main() -> (.status_code: Int32 = 0) := {
    values :: [0]UInt8 = ()
    borrowed_view ::= view(.array = $&values)
    pointer ::= data#(.t: UInt8)(.self = &borrowed_view).pointer
}
