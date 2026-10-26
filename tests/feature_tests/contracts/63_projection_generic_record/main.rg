Product<.Left: Type, .Right: Type>: Contract = (
    .Result : Type

    .multiply : (.left: Left, .right: Right) -> (.value: Result) where {}
)

implement Product<Int32, Int32> (.Result: Type = Int64, .multiply = _impl_multiply_193)

_impl_multiply_193 := (.left: Int32, .right: Int32) -> (.value: Int64) { value = 0 }

Box := <.T: Type> (.value: Product<T, T>.Result)

read_box := (.box: &Box<Int32>) -> (.value: Int64) { value = box&.value }

main := () -> () {
    box ::= Box<Int32>(42)
    if read_box(&box).value != 42 { abort }
}
