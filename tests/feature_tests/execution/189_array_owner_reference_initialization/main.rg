Resource := (.value: Int32)

implement Deinit<Resource> (.deinit = (.self: $&Resource) -> () {})

read := (.target: &Resource) -> (.result: Int32) { result = target&.value }

main := () -> (.status_code: Int32) {
    owners :: [2]Resource
    owners[0] = Resource(.value = 1)
    owners[1] = Resource(.value = 2)
    if owners[0].value != 1 or owners[1].value != 2 { abort }
    if read(.target = &owners[0]) != 1 { abort }
    if read(.target = &owners[1]) != 2 { abort }
    status_code = 42
}
