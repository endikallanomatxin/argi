#!/bin/bash
# Detectar el comando para copiar al portapapeles según el sistema operativo
if [[ "$(uname)" == "Darwin" ]]; then
    clipboard_cmd="pbcopy"
elif [[ "$(uname)" == "Linux" ]]; then
    # Se asume que xclip está instalado en Linux
    clipboard_cmd="xclip -selection clipboard"
elif [[ "$(uname)" =~ MINGW|CYGWIN ]]; then
    clipboard_cmd="clip"
else
    echo "Sistema operativo no soportado" >&2
    exit 1
fi

# Crear el contenido a copiar
{
    echo "----- ls -T -----"
    ls -T

    # Incluir recursivamente todos los archivos Markdown (.md)
    echo ""
    echo "----- Archivos Markdown Recursivos -----"
    # Se usa 'find' para buscar todos los archivos con extensión .md en el directorio actual y sus subdirectorios
    find . -type f -name "*.md" | while read mdfile; do
        echo ""
        echo "----- $mdfile -----"
        cat "$mdfile"
    done
} | $clipboard_cmd

echo "Contenido copiado al portapapeles."
