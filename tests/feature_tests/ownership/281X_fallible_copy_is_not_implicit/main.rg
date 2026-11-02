FallibleValue := (
    .value : Int32
)

implement FalliblyCopyable#(FallibleValue) (
    .reasons : Type = (..copy_failed)
    .copy    = (.self: &FallibleValue, .allocator: Virtual#(Allocator)) -> (
        .result : Errable#(.t: FallibleValue, .reasons: (..copy_failed))
    ) {

        assume allocator

        result = ..ok(.value = self&.value)
    }

)

main := () -> (.status_code: Int32) {
    first :: FallibleValue = (.value = 42)
    second ::= first
    status_code = second.value - 42
}
