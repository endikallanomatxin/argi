Kind#(.Value: Type): Contract = (
    .kind : (.value: &Value) -> (.result: Int32)
)

Alpha := (.value: Int32)

Beta := (.value: Int32)

_kind_alpha := (.value: &Alpha) -> (.result: Int32) {
    value
    result = 1
}

_kind_beta := (.value: &Beta) -> (.result: Int32) {
    value
    result = 2
}

implement Kind#(Alpha) (.kind = _kind_alpha)

implement Kind#(Beta) (.kind = _kind_beta)

kind_for := #(.t: Type) (.value: &t) -> (.result: Int32) {
    result = kind(.value = value).result
}

main := () -> (.status_code: Int32) {
    alpha: Alpha = (.value = 0)
    beta: Beta = (.value = 0)
    alpha_kind ::= kind_for#(.t: Alpha)(.value = &alpha).result
    beta_kind ::= kind_for#(.t: Beta)(.value = &beta).result
    status_code = alpha_kind * 10 + beta_kind
}
