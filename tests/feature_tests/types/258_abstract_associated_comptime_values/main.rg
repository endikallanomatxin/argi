AbstractMatrix#(.Participant: Type): Contract = (
    .t    : Type
    .rows : Int
    .cols : Int
)

Matrix := #(.t: Type, .rows: UIntNative, .cols: UIntNative) (.marker: Int32)

implement#(.t: Type, .rows: UIntNative, .cols: UIntNative) AbstractMatrix#(
    Matrix#(.t: t, .rows = rows, .cols = cols)
) (
    .t    : Type = t
    .rows : Int  = rows
    .cols : Int  = cols
)

require_dimensions := #(
    .matrix  : Type: AbstractMatrix#(.t: element, .rows = rows, .cols = cols),
    .element : Type,
    .rows    : UIntNative,
    .cols    : UIntNative,
) (.value: &matrix) -> () {}

main := (.system: System) -> (.status_code: Int32 = 0) {
    matrix ::= Matrix#(.t: Float32, .rows = 3, .cols = 4)(.marker = 0)
    require_dimensions(.value = &matrix)
}
