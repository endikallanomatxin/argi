finish := <.t: Type> (.value: t) -> () { while true {
        defer { continue }
        break
    } }

main := () -> () { finish<.t: Int32> (1) }
