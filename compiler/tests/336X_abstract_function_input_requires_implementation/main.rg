ExampleAbstract : Abstract = ()

use_value (.value: ExampleAbstract) -> (.status_code: Int32) := {
    status_code = 1
}

main () -> (.status_code: Int32) := {
    status_code = use_value(.value = 7)
}
