PythonValue<.Value: Type>: Contract = (
    .convert_value : (.self: &Python, .value: Value) -> (
        .result: Errable<Object, (..python_error)>
    )
)

to_object := <.Value: Type: PythonValue<Value>> (.self: &Python, .value: Value) -> (
    .result: Errable<Object, (..python_error)>
) {
    result = ~PythonValue<Value>.convert_value(.self = self, .value = ~value)
}
