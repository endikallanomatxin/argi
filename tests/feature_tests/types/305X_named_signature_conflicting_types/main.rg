Args := <.T: Type> (.left: T, .right: T)

Result := <.T: Type> (.result: T)

choose := <.T: Type> Args<T> -> Result<T> {
    result = left
}

main() -> () := {
    left: Int32 = 1
    right: Int64 = 2
    _ = choose(.left = left, .right = right)
}
