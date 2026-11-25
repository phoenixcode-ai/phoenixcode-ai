#!/usr/bin/env bash
#
# Que no entren datos personales en el repositorio: ni rutas de la carpeta de una persona (/Users/<nombre>,
# /home/<nombre>, C:\Users\<nombre>), ni nombres que el equipo no quiere ver escritos, ni commits firmados con una
# identidad que no sea la de la empresa. Guion común a los repos de PhoenixCode: si lo cambias, cópialo en los demás.
#
#   tools/sin-datos-personales.sh            # todo lo versionado
#   tools/sin-datos-personales.sh --staged   # solo lo que se va a commitear, y la identidad (lo corre el hook pre-commit)
#
# Los NOMBRES no se escriben aquí —sería meterlos en el repo para poder prohibirlos—: van en `.git/info/nombres-prohibidos`
# (uno por línea; git no versiona .git/info). Sin ese fichero solo se comprueban rutas e identidad.
# Las cuentas genéricas (usuario, user, runner, ec2-user…) no son de nadie y se aceptan: ver PERMITIDOS.
#
# POR QUÉ EXISTE: el 2026-11-24 aparecieron rutas `/Users/<persona>` en scripts versionados y un nombre personal como
# autor de buena parte del historial de varios repos.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

DOMINIO="${PHOENIXCODE_AUTHOR_DOMAIN:-phoenixcode.ai}"
RUTAS='(/Users/|/home/)[A-Za-z0-9._-]+/|[Cc]:\\\\?Users\\\\?[A-Za-z0-9._-]+'
PERMITIDOS='usuario|user|username|someone|me|you|x|dev|build|runner|runneradmin|ec2-user|ubuntu|node|app|svc|root|shared|test|\.\.\.'
NOMBRES_FICHERO="$(git rev-parse --git-common-dir)/info/nombres-prohibidos"
fallos=0

nombres=()
if [ -f "$NOMBRES_FICHERO" ]; then
  while IFS= read -r n; do [ -n "${n// }" ] && [ "${n:0:1}" != "#" ] && nombres+=("$n"); done < "$NOMBRES_FICHERO"
fi

# Deja pasar solo las líneas con alguna ruta personal que no sea de una cuenta genérica.
rutas_personales() {
  local l
  while IFS= read -r l; do
    if printf '%s\n' "$l" | grep -oE "$RUTAS" \
       | grep -qviE "^(/Users/|/home/|[Cc]:\\\\?Users\\\\?)(${PERMITIDOS})/?$"; then
      printf '%s\n' "$l"
    fi
  done
}

if [ "${1:-}" = "--staged" ]; then
  for quien in GIT_AUTHOR_IDENT GIT_COMMITTER_IDENT; do
    correo=$(git var "$quien" | sed -E 's/.*<([^>]*)>.*/\1/')
    if [[ "$correo" != *"@${DOMINIO}" ]]; then
      echo "✘ ${quien%_IDENT} es «${correo}»: los commits van con una identidad @${DOMINIO} (git config user.email)."
      fallos=1
    fi
  done
  contenido=$(git diff --cached -U0 --no-color | grep -E '^\+' | grep -vE '^\+\+\+ ')
  hallado=$(printf '%s\n' "$contenido" | grep -E "$RUTAS" | rutas_personales)
  if [ -n "$hallado" ]; then
    echo "✘ Lo que se va a commitear contiene una ruta de la carpeta de una persona (usa rutas relativas o \$HOME):"
    printf '%s\n' "$hallado" | head -5 | cut -c1-200 | sed 's/^/    /'
    fallos=1
  fi
  for n in "${nombres[@]+"${nombres[@]}"}"; do
    if printf '%s\n' "$contenido" | grep -qiF -e "$n"; then
      echo "✘ Lo que se va a commitear contiene un nombre de la lista local (.git/info/nombres-prohibidos)."
      fallos=1
    fi
  done
else
  hallado=$(git grep -n -I -E "$RUTAS" -- . ':!tools/sin-datos-personales.sh' 2>/dev/null | rutas_personales)
  if [ -n "$hallado" ]; then
    echo "✘ Rutas de la carpeta de una persona en ficheros versionados:"
    printf '%s\n' "$hallado" | cut -c1-200 | sed 's/^/    /'
    fallos=1
  fi
  for n in "${nombres[@]+"${nombres[@]}"}"; do
    if git grep -q -i -I -F -e "$n" -- . 2>/dev/null; then
      echo "✘ Un nombre de la lista local aparece en ficheros versionados:"
      git grep -n -i -I -F -e "$n" -- . | cut -c1-200 | sed 's/^/    /'
      fallos=1
    fi
  done
fi

[ "$fallos" -eq 0 ] && echo "✓ Sin rutas personales${nombres:+ ni nombres de la lista local}${1:+, identidad @${DOMINIO}}"
exit "$fallos"
