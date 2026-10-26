Box := <.T: Type> (.value: T)

implement<.T: Type> Add<Box<T>, Box<T>, (.left: &Box<T>, .right: &Box<T>)> (
    .Result : Type = Box<T>
    .add    = (.args: (.left: &Box<T>, .right: &Box<T>)) -> (.result: Result) {
        result = (.value = args.left&.value + args.right&.value)
    }
)

implement Add<Box<Int32>, Box<Int32>, (.left: &Box<Int32>, .right: &Box<Int32>)> (
    .Result : Type = Int32
    .add    = (.args: (.left: &Box<Int32>, .right: &Box<Int32>)) -> (.result: Result) {
        result = args.left&.value + args.right&.value
    }
)

sum := <.T: Type> (.left: &T, .right: &T) -> (
    .result: Add<T, T, (.left: &T, .right: &T)>.Result
) {
    result = ~[left + right]
}

main := () -> (.status_code: Int32 = 0) {
    a ::= Box<Int32>(7)
    b ::= Box<Int32>(5)
    specialized ::= &a + &b
    generic ::= sum(&a, &b)
    c ::= Box<UIntNative>(3)
    d ::= Box<UIntNative>(9)
    general ::= &c + &d
    if specialized != 12 or generic != 12 or general.value != 12 { status_code = 1 }
}
