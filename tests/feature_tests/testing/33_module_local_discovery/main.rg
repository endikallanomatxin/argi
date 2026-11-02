dependency := import("./dependency")

test local := () -> !() {
    testing.expect(dependency.answer() == 42)!
}

test shared_name := () -> !() {
    testing.expect(true)!
}
