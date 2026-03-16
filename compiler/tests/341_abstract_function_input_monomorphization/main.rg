ExampleAbstract : Abstract = ()

ExampleAbstract canbe Int32

use_value (.value: ExampleAbstract) -> (.status_code: Int32) := {
    status_code = value
}

main () -> (.status_code: Int32) := {
    status_code = use_value(.value = 7)
}
