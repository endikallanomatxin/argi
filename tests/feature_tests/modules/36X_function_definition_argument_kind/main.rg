dep := import("../32_qualified_comptime_calls/dep")

selected := dep.identity#(.t = 42)

main := () -> () {}
