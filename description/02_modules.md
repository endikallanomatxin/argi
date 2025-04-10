# Modules and imports

Folders as modules, como Go y odin. El nombre del módulo es el nombre de la carpeta.
Every file in a directory can see each other, same namespace.

Todo es un módulo y se importa como en Python:

- `import module` (module.función)
- `import module as m` (m.función)
- `import module asinplace` (función)

O igual mejor como zig:

- `m := import module`

Eso es para metaprogramación. Zig no tiene magia.
Realmente vamos a permitir que se le de un uso a eso.
No le vamos a meter magia? Seremos capacer de que sea coherente con el resto del lenguaje? 

> [!BUG] Decidir esto


## Locating modules

If the module starts with a . then it is relative to the current module. (inside)
If it starts with .. then it is relative to the parent module. (outside)

If it is just a name, then it is a module installed in the system.

/ are used to refer to modules inside other modules.


## Interpretation and imports

Lua tiene:
- require corre si no ha corrido ya (cache)
- dofile corre sin considerar el cache
- loadfile importa sin correr. Se puede correr a posteriori

Python por defecto corre todo lo importado linea a linea, y hay que hacer `if __name__ == "__main__":` para que no corra si se importa.

Tiene sentido que se pueda importar "scripts"?

Podríamos hacer:
- `run_if_not_yet(module)`
- `run(module)`
- `import(module)`


Igual es buena idea también separar los archivos que se pueden correr, de los que se pueden importar:

- Files inside a module: `script.rg`
- Scripts: `script.rgs`


