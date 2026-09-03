AbstractMatrix#(.rows: UIntNative) : Abstract = ()
Matrix : Type = (.marker: Int32)
Matrix implements AbstractMatrix#(.rows = 3)

require_four_rows#(.t: Type: AbstractMatrix#(.rows = 4))(.value: &t) -> () := {}

main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    matrix ::= Matrix(.marker = 0)
    require_four_rows(.value = &matrix)
}
