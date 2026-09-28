## Comptime

(from zig and jai)

It enables:
- Metaprogramming and macros written in the same language.
	This is particularly useful for building efficient and flexible abstractions.

Comptime is powerful, but it should remain secondary to the core language
model. It should not become the default escape hatch for missing features in
types, modules or dispatch.

Use `#` for this (inspired by Jai):

https://github.com/Ivo-Balbaert/The_Way_to_Jai/blob/main/book/26A_Metaprogramming.md

Yes:

- `name#(.param = value)` to define generics that will be monomorphized at compile time.

- `#run` to execute code at compile time.

- `#import` to import code from other files, like a C include.

- `#is_compile_time` to check whether code is executing at compile time.

- `#typeof` to get the type of a variable or expression at compile time.

    When applied to an abstract, it can be resolved because the abstract is
    monomorphized.

- `#if` for compile-time conditionals, as in C.
    `#if` is tested at compile time. When its condition is true, that block of
    code is compiled; otherwise, it is not.
    This is not the same as `#run if (...) { ... }`, which executes at compile
    time.

- `#atcalls` to execute code at compile time on every function call. For
    example, it can validate arguments and report compile-time errors.

    Perhaps all functions executed at compile time should be able to return an
    error.

    >[!TODO]
    >Find a way for libraries to use this to report compile-time errors or LSP
    >warnings when they are used incorrectly.

>[!IDEA] Ergonomics for allocator, stdio, async...
> #bringsystemallocator, #bringsystemstdo, #bringsystemasync
> When the file is saved, the necessary declarations will be modified to bring
> the required system resource.
> It deletes itself at save time.
>
> (This is closer to save time than compile time.) A different version of `#`
> could run when saving or during LSP analysis, and support macros that rewrite
> the file on save.

> Be careful with mechanisms that rewrite code in ways that are hard to see.
> They can make changes difficult to trace, even when convenient.


Unclear:

- `#maintain` to tell variables that received a value at compile time to keep it.

- `#code`

I do not like:

- `#insert` is somewhat like macros; using strings may be too messy.


> [!CHECK]
> I had ruled out using comptime for generics and interfaces, but it may be
> worth reconsidering. The example shown
> ThePrimeagen's discussion of `quak()` is interesting.
> https://youtu.be/Vxq6Qc-uAmE?si=-K0XTw2lAMFC10tM
> I like that part, but I dislike requiring `anytype`: it is too opaque and
> does not tell the user what data type is expected. It also does not provide
> everything generics need.
>
> The main difference is that function return types must use structural typing
> instead of nominal typing to be considered equivalent.
> That is awful.

https://www.scottredig.com/blog/bonkers_comptime/


> [!CHECK]
> In an interview with the creators of Odin and Elixir by ThePrimeagen and TJ,
> Ginger Bill says metaprogramming often reflects gaps in a language and can
> make programs very difficult to debug.
> It may be useful to see how this works in Zig and Jai before
> implementing it.
>
> A good rule of thumb: first finish the core language, then add comptime where
> it provides real value instead of merely filling gaps.

> [!IDEA] Comptime and incremental execution
> Explore a common execution model for comptime, REPL and compiled programs,
> reusing compiled specializations while their code, inputs and dependencies
> remain unchanged.
>
> One possible architecture is to lower each function to a compact, typed,
> serializable executable IR. A lightweight VM could execute that IR for
> comptime and interactive work, while LLVM consumes the same semantics for JIT
> and AOT native code. This would make REPL, comptime, JIT and normal compilation
> share most of the pipeline rather than becoming separate execution models.
>
> For REPL redefinition, decide whether existing callers use the new definition
> and what happens to live values when a type changes. Recompilation alone does
> not resolve how program state survives.
>
> A persistent `CompilerSession` could cache generated function specializations
> by something like `(FunctionId, concrete type arguments, comptime values)`,
> generating code when first required or after invalidation by changes to its
> code or dependencies.
