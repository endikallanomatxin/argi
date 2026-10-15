dep := import("../32_qualified_comptime_calls/dep")

main() -> () := {
    value := dep.identity#(Int32)
}
