Box := #(.T: Type) (.value: T)

implement#(.T: Type) Add#(&Box#(T), &Box#(T)) (
    .Result : Type = Box#(T)
    .add    = (.left: &Box#(T), .right: &Box#(T)) -> (.result: Result) {
        result = (.value = left&.value + right&.value)
    }
)

implement Add#(&Box#(Int32), &Box#(Int32)) (
    .Result : Type = Int32
    .add    = (.left: &Box#(Int32), .right: &Box#(Int32)) -> (.result: Result) {
        result = left&.value + right&.value
    }
)

sum := #(.T: Type) (.left: &T, .right: &T) -> (
    .result: Add#(&T, &T).Result
) {
    result = ~[left + right]
}

main := () -> (.status_code: Int32 = 0) {
    a ::= Box#(Int32)(7)
    b ::= Box#(Int32)(5)
    specialized ::= &a + &b
    generic ::= sum(&a, &b)
    c ::= Box#(UIntNative)(3)
    d ::= Box#(UIntNative)(9)
    general ::= &c + &d
    if specialized != 12 or generic != 12 or general.value != 12 { status_code = 1 }
}
