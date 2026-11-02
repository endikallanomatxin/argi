invalid := #(.T: Type) (.marker: T, .order: Ordering) -> (.ok: Bool) {
    ok = order == ..missing
}

main := () -> () {
    order: Ordering = ..less
    invalid#(Int32)(1, order)
}
