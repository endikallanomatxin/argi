fail := () -> (.result: Int32 = 0) { abort }

main := () -> () {
    values :: [2]Int32 = (1, 2)
    index :: UIntNative = 2
    values[index] = fail()
}
