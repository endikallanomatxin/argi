AbstractMatrix#(
    .t: Type,
    .rows: UIntNative,
    .cols: UIntNative,
) : Abstract = ()

Matrix#(
    .t: Type,
    .rows: UIntNative,
    .cols: UIntNative,
) : Type = (.marker: Int32)

Matrix#(
    .t: Type,
    .rows: UIntNative,
    .cols: UIntNative,
) implements AbstractMatrix#(
    .t: t,
    .rows = rows,
    .cols = cols,
)

require_dimensions#(
    .matrix: Type: AbstractMatrix#(
        .t: element,
        .rows = rows,
        .cols = cols,
    ),
    .element: Type,
    .rows: UIntNative,
    .cols: UIntNative,
)(.value: &matrix) -> () := {}

main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    matrix ::= Matrix#(.t: Float32, .rows = 3, .cols = 4)(.marker = 0)
    require_dimensions(.value = &matrix)
}
