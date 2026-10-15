ExampleAbstract#(.Participant: Type): Contract = ()

use_value#(.Value: Type: ExampleAbstract)(.value: Value) -> (.status_code: Int32) := {
    status_code = 1
}

main () -> (.status_code: Int32) := {
    status_code = use_value(.value = 7)
}
