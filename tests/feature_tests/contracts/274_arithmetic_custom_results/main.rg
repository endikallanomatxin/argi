Input := (.number: Int32)

Output := (.number: Int32)

implement Subtract#(&Input, &Input) (
    .Result   : Type = Output
    .subtract = (.left: &Input, .right: &Input) -> (.result: Result) {
        result = (.number = [left&.number - right&.number])
    }
)

implement Multiply#(&Input, &Input) (
    .Result   : Type = Int64
    .multiply = (.left: &Input, .right: &Input) -> (.result: Result) {

        result = [[left&.number * right&.number] | convert#(.to: Int64)(_)]
    }
)

implement Divide#(&Input, &Input) (
    .Result : Type = Int32
    .divide = (.left: &Input, .right: &Input) -> (.result: Result) {
        result = [left&.number / right&.number]
    }
)

implement Remainder#(&Input, &Input) (
    .Result    : Type = Int32
    .remainder = (.left: &Input, .right: &Input) -> (.result: Result) {
        result = [left&.number % right&.number]
    }
)

multiply_values := #(.T: Type) (.left: &T, .right: &T) -> (.result: Multiply#(&T, &T).Result) {
    result = ~[left * right]
}

main := () -> (.status_code: Int32 = 0) {
    a ::= Input(9)
    b ::= Input(2)
    difference ::= &a - &b
    product ::= &a * &b
    generic ::= multiply_values(&a, &b)
    quotient ::= &a / &b
    remainder ::= &a % &b
    if [
        difference.number != 7
        or product != 18
        or generic != 18
        or quotient != 4
        or remainder != 1
    ] { status_code = 1 }
}
