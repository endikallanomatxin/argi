ExampleAbstract#(.Participant: Type): Contract = ()

use_value := #(.Value: Type: ExampleAbstract) (.value: Value) -> (.status_code: Int32) {
    status_code = 0
}
