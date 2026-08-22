mix(.left: $$&Int32, .right: $$&Int32) -> () := {}

main() -> (.status_code: Int32) := {
    values :: [2]Int32 = (1, 2)
    index :: UIntNative = 0
    mix(.left = $$&values[index], .right = $$&values[1])
    status_code = 0
}
