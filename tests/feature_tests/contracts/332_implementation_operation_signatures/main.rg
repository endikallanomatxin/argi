Factory#(.Target: Type): Contract = (.make: _)

Point := (.x: Int32)

Box := #(.T: Type) (.value: T)

FirstProvider := (.flag: Bool)

SecondProvider := (.value: Int32)

Borrow#(.Target: Type): Contract = (.borrow: _)

implement#(.T: Type) Borrow#(Box#(T)) (
    .borrow = (.self: &Box#(T)) -> (.result: &T) { result = &self&.value }
)

Counter := (.value: Int32)

implement Factory#(Point) (
    .make = (.x: Int32 = 42) -> (.result: Point) {
        result = (.x = x)
    }
)

implement#(.T: Type) Factory#(Box#(T)) (
    .make = #(.Provider: Type) (.value: T, .provider: &Provider) -> (.result: Box#(T)) {
        result = (.value = ~value)
    }
)

from_value := (.value: Int32 = 42) -> (.result: Counter) { result = (.value = value) }

implement Factory#(Counter) (.make = from_value)

compute := () -> (.result: Int32) {
    first: FirstProvider = (.flag = true)
    second: SecondProvider = (.value = 1)
    point ::= Factory#(Point).make()
    left ::= Factory#(Box#(Int32)).make(.value = point.x, .provider = &first)
    right ::= Factory#(
        Box#(Int32)
    ).make#(.Provider: SecondProvider)(.value = 42, .provider = &second)
    if left.value != right.value { abort }
    borrowed ::= Borrow#(Box#(Int32)).borrow(.self = &left)
    if borrowed&!= 42 { abort }
    counter ::= Factory#(Counter).make()
    result = counter.value
}

known ::= #run () -> (.result: Int32) { result = compute() }

main := () -> (.status_code: Int32) {
    if known != 42 { abort }
    status_code = compute()
}
