identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }

defaulted := #(.F: Function = identity#(Int32)) (.value: Int32) -> (.result: Int32) { result = F(.value = value) }

main := () -> () {
    args: inputs_of#(identity#(Int32)) = (.value = 42)
    result: result_of#(identity#(.T: Int32)) = invoke#(identity#(Int32))(.args = ~args)
    if result != 42 { abort }
    if defaulted(.value = 42) != 42 { abort }
}
