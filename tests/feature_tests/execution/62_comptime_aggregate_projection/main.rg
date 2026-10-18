values() -> (.data: (.items: [2](.answer: Int32))) := {
    data = (.items = ((.answer = 20), (.answer = 42)))
}

identity(.value: Int32) -> (.result: Int32 = value) := {}

main() -> (.status_code: Int32 = 0) := {
    status_code = #run identity(.value = values().items[1].answer)
}
