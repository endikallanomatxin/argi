# Modules and project layout

At the repository level, the official library is split into:

- `core/`: always available base library
- `more/`: official extended library, imported explicitly

User code still uses the same folder-based module model.

Folders as modules, como Go y odin. El nombre del módulo es el nombre de la
carpeta.

Every file in a directory can see each other, same namespace.

The module system should stay deliberately boring. This is infrastructure, not
one of the places where the language needs to be especially clever.

## Current status

Today the compiler implements:

- folder-level modules: all `.rg` files in the same directory share namespace
- `core/` autoimported
- `more/` imported explicitly
- named imports only: `m := #import("...")`
- import path kinds:
  - `./dep` relative to the current module
  - `../dep` relative to the parent module
  - `.../dep` relative to the project root
- `_private_name` hidden across module boundaries
- bundled `core` modules may use each other's private helpers; user modules
  cannot access them
- transitive imports
- import cycle detection

`#import("...")` as a standalone statement is intentionally not supported.

## Project layout

There is two layout conventions:

```
simple_module/
├── README.md
├── module.rgstruct
├── submodule/
│   ├── file1.rg
│   ├── file2.rg
│   └── file3.rg
└── submodule2/
    ├── file1.rg
    ├── file2.rg
    └── file3.rg

project/
│
├── README.md
│
├── project.rgstruct
│
├── entrypoints/              -- required for executable creation (optional otherwise)
│   └── module_to_compile/
│       ├── file1.rg
│       ├── file2.rg
│       └── file3.rg
│
├── public/                   -- required for libraries (optional otherwise)
│   ├── module1/
│   │   ├── file1.rg
│   │   ├── file2.rg
│   │   └── file3.rg
│   └── module2/
│       ├── file1.rg
│       ├── file2.rg
│       └── file3.rg
│
├── private/                  -- always optional
│   ├── module1/
│   │   ├── file1.rg
│   │   ├── file2.rg
│   │   └── file3.rg
│   └── module2/
│       ├── file1.rg
│       ├── file2.rg
│       └── file3.rg
│
└── results/
    └── bin/                  -- When compiling for yourself.
    │   └── module_that_becomes_executable
    └── dist/                 -- When distributing the project.
        ├── linux_x86_64_installer
        ├── linux_arm64_installer
        ├── macos_x86_64_installer
        ├── macos_arm64_installer
        ├── windows_x86_64_installer
        └── windows_arm64_installer
    └── .gitignore
```

No se si private/public o internal/external es mejor.

Conviene priorizar una convención simple y estable frente a una demasiado
configurable.


## Importing modules

`m := #import("module_path")`

Bare names are resolved under `more/`.

If the module starts with `./` then it is relative to the current module.
If it starts with `../` then it is relative to the parent module.
If it starts with `.../` then it is relative to the root of the project.

Examples:

```rg
json := #import("codecs/serialization/json")
sibling := #import("./sibling")
parent_dep := #import("../shared")
root_dep := #import(".../app/shared")
```

Imports should always be bound to a name.


## Importing stuff from modules

Access is explicit through the module binding:

```rg
math := #import("math/linear_algebra")
result := math.solve(...)
```

This keeps name origin visible and avoids implicit namespace pollution.

> [!NOTE]
> que sea una sintaxis acorde al código normal permite programar imports
> en compile time. No se hasta qué punto puede perjudicar, respecto a algo más
> simple como go)


## C import

To import C code, you can use the `#c_import` directive:

```rg
some_c_lib = #c_import("c_module.h")
```

It automatically converts C types to argi types:

- Function calls accept structs and return structs, with the names as arguments.
- ..

A lot of the standard more library depends on external libraries as:

- `blas`/`lapack` for linear algebra.
- `openssl` for cryptography.
- `zlib` for compression.
- `ffmpeg` for codecs.

If the library is not recognized when compiling a module using any of those, it
will throw an error requiring to install the library and link it properly.

También tiene que haber una opción para que al distribuir se incluyan las
librerías que necesita cada arquitectura, eso estaría bien.


## Packages

```bash
argi add <package>
```

```bash
argi remove <package>
```

Se descargan todos en un entorno global. No se hacen entornos virtuales. Como NIX y como go.

En el root del proyecto se tiene que guardar lo que iria en go.mod y go.sum

## Kickstarter

```
argi init app
```

o

```
argi init lib
```
