Input := (.number: Int32)

Output := (.number: Int32)

implement Subtract#(Input, Input, (.left: &Input, .right: &Input)) (
    .Result   : Type = Output
    .subtract = (.args: (.left: &Input, .right: &Input)) -> (.result: Result) {
        result = (.number = [args.left&.number - args.right&.number])
    }
)

implement Multiply#(Input, Input, (.left: &Input, .right: &Input)) (
    .Result   : Type = Int64
    .multiply = (.args: (.left: &Input, .right: &Input)) -> (.result: Result) {
        result = [[args.left&.number * args.right&.number] | convert#(.to: Int64)(_)]
    }
)

implement Divide#(Input, Input, (.left: &Input, .right: &Input)) (
    .Result : Type = Int32
    .divide = (.args: (.left: &Input, .right: &Input)) -> (.result: Result) {
        result = [args.left&.number / args.right&.number]
    }
)

implement Remainder#(Input, Input, (.left: &Input, .right: &Input)) (
    .Result    : Type = Int32
    .remainder = (.args: (.left: &Input, .right: &Input)) -> (.result: Result) {
        result = [args.left&.number % args.right&.number]
    }
)

multiply_values := #(.T: Type) (.left: &T, .right: &T) -> (
    .result: Multiply#(T, T, (.left: &T, .right: &T)).Result
) { result = ~[left * right] }

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
