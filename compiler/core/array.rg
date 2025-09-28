Array#(.t: Type) : Type = (
    .data: $&t,
    .length: Int32 = 0,
)

init#(.t: Type) (.a: $&Array#(.t), .source: ListLiteral#(.t)) -> () := {

    l : Int32 = length(.value = source)
    data_ptr : &t = allocate(.count = l, .type = t)

    for i: Int32 = 0; i < l; i = i + 1 {
        element_ptr : $&t = data_ptr + i
        element_ptr& = src[i]
    }

    a& = (
        .data = data_ptr,
        .length = l,
    )

}

deinit#(.t: Type) (.a: $&Array#(.t)) -> () := {
    arr :: Array#(.t) = a&
    ptr : &Any = arr.data
    free(.pointer = ptr)

    a& = (
        .data = arr.data,
        .length = 0,
    )
}

operator get[]#(.t: Type)(.self: &Array#(.t), .i: Int32) -> (.value: t) := {
    arr :: Array#(.t) = self&
    element_ptr : &t = arr.data + i
    value = element_ptr&
}

operator set[]#(.t: Type)(.self: $&Array#(.t), .i: Int32, .value: t) -> () := {
    arr :: Array#(.t) = self&
    element_ptr : $&t = arr.data + i
    element_ptr& = value
}
