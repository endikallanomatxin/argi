main() -> (.status_code: Int32 = 0) := {
    values :: [0]UInt8 = ()
    view ::= array_view#(.n = 0, .t: UInt8)(.array = $&values).view
    pointer ::= data#(.t: UInt8)(.self = &view).pointer
}
