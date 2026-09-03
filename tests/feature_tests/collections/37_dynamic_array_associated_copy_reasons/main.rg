..copy_failed

FallibleValue : Type = (
    .value: Int32
)

copy(.self: &FallibleValue) -> (.result: Errable#(
    .t: FallibleValue,
    .reasons: (..copy_failed),
)) := {
    result = ..ok(.value = self&.value)
}

FallibleValue implements FalliblyCopyable#(.reasons: (..copy_failed))

require_array_reasons#(
    .t: Type: FalliblyCopyable#(.reasons: (..copy_failed, ..out_of_memory)),
)(.value: &t) -> () := {}

main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    source ::= DynamicArray#(.t: FallibleValue)(.capacity = 1)
    #defer deinit#(.t: FallibleValue)(.self = $&source)
    value ::= FallibleValue(.value = 42)
    push_assume_capacity#(.t: FallibleValue)(.self = $&source, .value = ~value)

    require_array_reasons(.value = &source)

    nested ::= DynamicArray#(.t: DynamicArray#(.t: FallibleValue))(.capacity = 1)
    #defer deinit#(.t: DynamicArray#(.t: FallibleValue))(.self = $&nested)
    require_array_reasons(.value = &nested)
}
