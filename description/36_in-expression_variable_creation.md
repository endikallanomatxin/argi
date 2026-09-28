## In-expression variable creation

In most languages, when function calls are nested, you cannot pass a reference to one call's output as another call's input. The intermediate variables do not exist, so references to them cannot be created.
This makes the language less ergonomic, especially when piping function calls.

In our language, when calls are nested or piped:

- Intermediate variables are created automatically.
- If the function using a variable needs an `&` reference, the variable is constant; if it needs `$&`, the variable is mutable.
- Unless a variable is kept inside the next function, it is deinitialized after that call.


Examples:

Builder pattern:

```
body :=
      SketchBuilder()
    | trapezoid(&_, 4, 3, 90)
    | fillet(&_, 0.25)
    | extrude(&_, 0.1)
    | finish(&_)
```

Function that needs a reference for parallel processing:

```
result :=
      load_png("image.png")
    | keep _ with result
    | parallel_process_that_only_reads(&_)
    | parallel_process_that_writes(~&_)
```
