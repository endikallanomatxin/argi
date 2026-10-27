produce := #(.Result: Type) () -> Result {}

main := () -> () { produce#(Int32)() }
