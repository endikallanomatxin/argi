# Modules and imports

Folders as modules, como Go y odin. El nombre del módulo es el nombre de la carpeta.
Every file in a directory can see each other, same namespace.

Todo es un módulo y se importa como en Python:

- `import module` (module.función)
- `import module as m` (m.función)
- `import module asinplace` (función)

O igual mejor como zig:

- `m ::= import module`


## Interpretation and imports

Lua tiene:
- require corre si no ha corrido ya (cache)
- dofile corre sin considerar el cache
- loadfile importa sin correr. Se puede correr a posteriori

Python por defecto corre todo lo importado linea a linea, y hay que hacer `if __name__ == "__main__":` para que no corra si se importa.

Tiene sentido que se pueda importar "scripts"?

Igual podríamos hacer algo como:

interpret("script.rg")


Igual es buena idea también separar los archivos que se pueden correr, de los que se pueden importar:

- Libraries: `script.rgl`
- Scripts: `script.rgs`


