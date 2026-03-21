ExampleAbstract : Abstract = ()

Int32 implements ExampleAbstract
Char implements ExampleAbstract

value_code (.value: Int32) -> (.r: Int32) := {
    r = 1
}

value_code (.value: Char) -> (.r: Int32) := {
    r = 2
}

use_value (.value: ExampleAbstract) -> (.status_code: Int32) := {
    status_code = value_code(.value = value).r
}

main () -> (.status_code: Int32) := {
    status_code = use_value(.value = 7) + use_value(.value = 'A')
}
