Value := <.T: Type> (.number: T)

implement<.T: Type: ImplicitlyCopyable> ImplicitlyCopyable<Value<T>> ()

calls :: Int32 = 0

implement<.T: Type> Equal<Value<T>, Value<T>, (.left: Value<T>, .right: Value<T>)> (
    .equal = (.args: (.left: Value<T>, .right: Value<T>)) -> (.ok: Bool) {
        calls = calls + 1
        ok = args.left.number == args.right.number
    }
)

implement Equal<Value<Int32>, Value<Int32>, (.left: Value<Int32>, .right: Value<Int32>)> (
    .equal = (.args: (.left: Value<Int32>, .right: Value<Int32>)) -> (.ok: Bool) {
        calls = calls + 10
        ok = args.left.number == args.right.number
    }
)

same := <.T: Type> (.left: T, .right: T) -> (.ok: Bool) { ok = left == right }

different := <.T: Type> (.left: T, .right: T) -> (.ok: Bool) { ok = left != right }

main := () -> (.status_code: Int32 = 0) {
    a ::= Value<Int32>(7)
    b ::= Value<Int32>(9)
    c ::= Value<UIntNative>(7)
    if a == b { status_code = 1 }
    if a != b == false { status_code = 2 }
    if same(a, a).ok == false { status_code = 3 }
    if different(a, b).ok == false { status_code = 4 }
    if same(c, c).ok == false { status_code = 5 }
    if calls != 41 { status_code = 6 }
}
