compute() -> (.result: Bool = true) := {}

result#(.n: Int32)() -> (.value: Int32 = n) := {}

main() -> (.status_code: Int32 = 0) := {
    status_code = result#(.n = #run compute())()
}
