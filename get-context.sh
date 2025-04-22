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

    echo ""
    echo "----- Archivos Markdown Recursivos -----"
    find . -type f \( -name "*.md" -o -name "*.rg" \) | while read file; do
        echo ""
        echo "----- $file -----"
        cat "$file"
    done
} | $clipboard_cmd

echo "Contenido copiado al portapapeles."
