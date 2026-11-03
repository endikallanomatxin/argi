double := (.x: Int32) -> (.result: Int32) { result = x * 2 }
empty := () -> () {}
pair := (.x: Int32) -> (.first: Int32, .second: Bool) {
    first = x
    second = true
}

Task := #(.F: Function) (
    .args: inputs_of#(F)
)

run_task := #(.F: Function) (.task: Task#(F)) -> (.result: result_of#(F)) {
    result = F(.x = task.args.x)
}

compile_result := #(.F: Function) () -> (.result: result_of#(F)) {
    result = #run () -> (.result: result_of#(F)) {
        args ::= prepare_args#(F)(.args = (.x = 21))
        result = invoke#(F)(.args = ~args)
    }
}

main := () -> () {
    task: Task#(double) = (.args = (.x = 21))
    result := run_task#(double)(.task = task)
    if result != 42 { abort }
    if compile_result#(double)() != 42 { abort }
    inputs: inputs_of#(pair) = (.x = 3)
    outputs: outputs_of#(double) = (.result = 42)
    value: result_of#(double) = outputs.result
    pair_result: result_of#(pair) = pair(.x = inputs.x)
    empty_inputs: inputs_of#(empty) = ()
    empty_outputs: outputs_of#(empty) = ()
    no_result: result_of#(empty) = empty()
    if pair_result.first != 3 or value != 42 { abort }
}
