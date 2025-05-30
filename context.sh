#!/usr/bin/env bash
# -------------------------------------------------------------
# context.sh  –  Copia al portapapeles un snapshot del repo
#                con índice, diff y bloques con fences Markdown
# -------------------------------------------------------------
set -euo pipefail

# ---------- Opciones por defecto ----------
declare -a INCLUDE_DIRS=()   # --dirs a,b
declare -a EXCLUDE_DIRS=()   # --exclude x,y
FLAG_TOC=true                 # --no-toc  para desactivar
FLAG_GITDIFF=true             # --no-git-diff para desactivar

# ---------- Parseo de argumentos ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dirs)
      IFS=',' read -ra INCLUDE_DIRS <<< "$2"
      shift 2
      ;;
    --exclude)
      IFS=',' read -ra EXCLUDE_DIRS <<< "$2"
      shift 2
      ;;
    --no-toc)
      FLAG_TOC=false
      shift
      ;;
    --no-git-diff)
      FLAG_GITDIFF=false
      shift
      ;;
    -*)
      echo "Opción desconocida: $1" >&2
      exit 1
      ;;
    *)
      shift
      ;;
  esac
done

# ---------- Comando de portapapeles ----------
case "$(uname)" in
  Darwin)         clipboard_cmd="pbcopy" ;;
  Linux)          clipboard_cmd="xclip -selection clipboard" ;;
  MINGW*|CYGWIN*) clipboard_cmd="clip"   ;;
  *)
    echo "SO no soportado" >&2
    exit 1
    ;;
esac

# ---------- Helpers ----------
in_excluded_dir() {
  [[ ${#EXCLUDE_DIRS[@]} -eq 0 ]] && return 1
  for ex in "${EXCLUDE_DIRS[@]}"; do
    [[ "$1" == *"/$ex/"* ]] && return 0
  done
  return 1
}

print_file() {
  file="$1"
  ext="${file##*.}"
  case "$ext" in
    md)   lang=md   ;;
    rg)   lang=rg   ;;
    sh)   lang=bash ;;
    *)    lang=     ;;
  esac

  echo
  echo "----- $file -----"
  printf '```%s\n' "$lang"
  cat "$file"
  echo '```'
}

process_dir() {
  find "$1" -type f \( -name '*.md' -o -name '*.rg' \) | sort \
    | while read -r f; do
        in_excluded_dir "$f" && continue
        print_file "$f"
      done
}

# ---------- Generar salida ----------
{
  echo "===== ls -T ====="
  ls -T
  echo

  # ----- TOC -----
  if $FLAG_TOC; then
    echo "===== Índice ====="
    PATTERN=".git"
    if [[ ${#EXCLUDE_DIRS[@]} -gt 0 ]]; then
      PATTERN+="|$(IFS='|'; echo "${EXCLUDE_DIRS[*]}")"
    fi
    if [[ ${#INCLUDE_DIRS[@]} -gt 0 ]]; then
      for d in "${INCLUDE_DIRS[@]}"; do
        [[ -d $d ]] && tree "$d" -I "$PATTERN"
      done
    else
      tree . -I "$PATTERN"
    fi
    echo
  fi

  # ----- git diff -----
  if $FLAG_GITDIFF && command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "===== git status ====="
    git status -s
    echo
    echo "===== Diff corto (HEAD~1..HEAD) ====="
    git --no-pager diff --stat HEAD~1
    echo
  fi

  # ----- Archivos -----
  echo "===== Archivos Markdown / RG ====="
  if [[ ${#INCLUDE_DIRS[@]} -gt 0 ]]; then
    for d in "${INCLUDE_DIRS[@]}"; do
      if [[ -d $d ]]; then
        echo
        echo ">>> Directorio: $d"
        process_dir "$d"
      else
        echo ">>> Directorio NO encontrado: $d" >&2
      fi
    done
  else
    echo
    echo ">>> Directorio: ."
    process_dir .
  fi
} | $clipboard_cmd

echo "Contenido copiado al portapapeles."
