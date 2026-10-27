Readable #(.T: Type ): Contract = ()
Writable #(.T: Type ): Contract = (Readable #( T ))
Cell: Type = ()
implement Writable #( Cell ) ()
main := () -> () {}
