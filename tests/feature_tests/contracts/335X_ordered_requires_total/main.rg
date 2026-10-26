requires_total := <.T: Type: TotalOrder<T, T>> (.value: T) -> () {}

main := () -> () {
    value: Float32 = 0.0
    requires_total(value)
}
