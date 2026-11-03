add := (.left: Int32, .right: Int32) -> (.result: Int32) {
    result = left + right
}

Task := #(.F: Function) (
    .args: inputs_of#(F)
)

run_task := #(.F: Function) (.task: Task#(F)) -> (.result: result_of#(F)) {
    result = invoke#(F)(.args = ~task.args).result
}

Resource := (.value: Int32)
drops :: Int32 = 0
implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + 1 }
)

consume := (.item: Resource) -> (.result: Int32) {
    owned ::= ~item
    result = owned.value
}

increment := (.value: $&Int32) -> () {
    value&= value&+ 1
}

main := () -> () {
    task ::= Task#(add)(.args = (.left = 20, .right = 22))
    if run_task#(add)(.task = ~task).result == 42 {} else { abort }
    if true {
        owned: inputs_of#(consume) = (.item = Resource(42))
        if invoke#(consume)(.args = ~owned).result != 42 { abort }
    }
    if drops != 1 { abort }
    number :: Int32 = 41
    borrowed: inputs_of#(increment) = (.value = $&number)
    invoke#(increment)(.args = ~borrowed)
    if number != 42 { abort }
}
