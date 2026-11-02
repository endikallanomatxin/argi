main := () -> (.status_code: Int32 = 0) {
    values :: [2]Int32 = (10, 20)
    index :: UIntNative = 2
    values[index] = 99
}
