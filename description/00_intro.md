# Principles

- GENERAL PURPOSE PROGRAMMING LANGUAGE


- SOLVE THE 2 LANGUAGES PROBLEM

	Permitir control de bajo nivel, como rust o zig, pero con un comportamiento por defecto que de una experiencia para nuevos más cercana a python.

	Basically it is similar to zig, but with friendly defaults for beginners, to make it fill the niche that python fills.

	No es necesario entender todos los detalles para empezar a usarlo, pero el propio compilador te guiará a aprenderlos según vayas buscando más control. Abstracción clara, dispuesta a explicarse a sí misma. de fácil descubrimiento.


- CONSISTENT

	Clear syntax that minimizes symbol reuse.


- OPINIONATED

	There is always one obvious way to do something.
	The canonical way of doing things will sometimes even be imposed by the
	compiler (naming conventions, reserved names, code formatting...).


- EXPRESSIVE

	Intent of the developer is clear.


- SIMPLE BUT NOT TOO MUCH

	As few features as possible, without sacrificing expressiveness.

	> Having too few features can sometimes make the language less expressive.
	>
	> For example:
	> - generics in zig, are stretching too far the comptime thing.
	> - the lack of generics in go, made it hard to write reusable code.


- GREAT TOOLING

	Compiled or interpreted.
	Official formatter from the lsp.


# Key characteristics

- Functions

    - take a struct and return a struct.

    - have multiple dispatch, considering the types of the fields inside the struct.

    - their side effects are always explicit.
        (Capability based programming, dependency inyection).

- Code organization and polimorphism:

    - No objects

    - No inheritance. Interface-like abstract types.

    - Has generics.

- Errable and Nullable types.

