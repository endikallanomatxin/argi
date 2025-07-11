# Modules and imports

Folders as modules, como Go y odin. El nombre del módulo es el nombre de la
carpeta.

Every file in a directory can see each other, same namespace.

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

## Building

- Es más limpio que sea declarativo (pyproject.toml)

- Es más versátil que sea procedural (build.zig)

Hay que encontrar un balance entre ambos.

project.rgstruct

```rg
.name                 = "Project Name"

.version              = "1.0.0"

.description          = "A brief description of the project."

.readme               = "README.md"

.minimum_argi_version = "0.1.0"

.authors = (
    "Jhon Snow"
    "Arya Stark"
)

.license = ..MIT

.dependencies = (
    "module_one" = (
        .path      = "http://example.com/module_one/"
        .version   = ">1.2.3"
        .lock_hash = "abcd1234efgh5678ijkl9012mnop3456qrst7890uvwx"
    )
    "module_two" = (
        .path      = "https://example.com/module_two/"
        .version   = ">2"
        .lock_hash = "wxyz1234abcd5678efgh9012ijkl3456mnop7890qrst"
    )
    -- TODO: Pensar si separa los locks en otro archivo.
)

.commands = (

    -- Deben poder correr at compile time

    "build" = default_executable_creation (.module = "./entrypoints/main")
    -- o para librerías estáticamente linkadas.
    -- "build" = default_dynamically_linked_library_creation (.module = ".")

    "test"  = default_testing (.all_inside_folder = ".")

    "install" = (.ct: CommandContext) -> () {
        ct.do("build")
        -- Aquí procedural
    }

    "uninstall" = (.ct: CommandContext) -> () {
        -- Aquí procedural
    }

    "distribute" = (.ct: CommandContext) -> () {
        -- llena la carpeta dist/ con los compilados para todas las plataformas
    }

    "custom" = (.ct: CommandContext) -> () {
        -- Aquí procedural
    }
)
```


## Importing modules

`m := #import("module_path")`

If it is just a name, it is checked in the dependencies table of the closest root.

If the module starts with a . then it is relative to the current module. (inside)
If it starts with .. then it is relative to the parent module. (outside)
If it starts with / then it is relative to the root of the project.

/ are used to refer to modules inside other modules.


## Importing stuff from modules

To import stuff from other modules:

- `some_function := #import("./module/").some_function`

- `(one, two) := #import("./module/").(one, two)`

    o

    `one = m.one`
    `two = m.two`

(que sea una sintaxis acorde al código normal permite programar imports en
compile time. No se hasta qué punto puede perjudicar, respecto a algo más
simple como go)


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


