ExampleAbstract#(.Participant: Type): Contract = ()

implement ExampleAbstract#(Int32) ()

use_value := #(.Value: Type: ExampleAbstract) (.value: Value) -> () {}

main := () -> (.status_code: Int32 = 0) {
    x: Int32 = 0
    use_value(.value = x)
}
