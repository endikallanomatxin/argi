api := import("./api")
read_integer := (.value: &Int32) -> (.result: Int32) { result = value& }
implement api.Reader#(Int32) (
    .Result: Type = Int32
    .read = read_integer
)
main := () -> () {}
