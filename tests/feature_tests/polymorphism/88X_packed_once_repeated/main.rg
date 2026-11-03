setup := once () -> () {}

main := () -> () {
    first: inputs_of#(setup) = ()
    second: inputs_of#(setup) = ()
    invoke#(setup)(.args = ~first)
    invoke#(setup)(.args = ~second)
}
