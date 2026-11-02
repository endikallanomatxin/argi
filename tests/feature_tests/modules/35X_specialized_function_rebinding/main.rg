dep := import("../32_qualified_comptime_calls/dep")

main := () -> () {
    selected := dep.identity#(Int32)
    _ ::= selected#(Bool)(.value = true)
}
