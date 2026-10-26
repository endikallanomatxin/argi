ExampleAbstract<.Participant: Type>: Contract = ()

implement ExampleAbstract<Int32> ()

use_value := <.Value: Type: ExampleAbstract> (.value: Value) -> (.status_code: Int32) {
    status_code = value
}

main := () -> (.status_code: Int32) {
    status_code = use_value(.value = 7)
}
