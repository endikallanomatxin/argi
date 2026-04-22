NumberValue : CUnion = (
    .small: Int16,
    .large: Int64,
)

main() -> (.status_code: Int32) := {
    value :: NumberValue = (.small = 7)
    if value.small != 7 {
        status_code = 1
        return
    }

    value.large = 42
    if value.large != 42 {
        status_code = 2
        return
    }

    union_size :: UIntNative = size_of(.type = NumberValue)
    if union_size != 8 {
        status_code = 3
        return
    }

    union_alignment :: UIntNative = alignment_of(.type = NumberValue)
    if union_alignment != 8 {
        status_code = 4
        return
    }

    status_code = 0
}
