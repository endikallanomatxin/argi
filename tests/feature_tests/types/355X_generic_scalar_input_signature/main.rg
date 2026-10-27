accept_record := #(.Args: Type) Args -> () {}

main := () -> () {
    selected := accept_record#(Int32)
    selected(42)
}
