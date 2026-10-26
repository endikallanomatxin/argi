AbstractMatrix<.Participant: Type>: Contract = (.rows: Int)
Matrix := (.marker: Int32)
implement AbstractMatrix<Matrix> (.rows: Int = 3)

require_four_rows := <.t: Type: AbstractMatrix<.rows = 4>> (.value: &t) -> ()  {}

main := (.system: System) -> (.status_code: Int32 = 0)  {
    matrix ::= Matrix(.marker = 0)
    require_four_rows(.value = &matrix)
}
