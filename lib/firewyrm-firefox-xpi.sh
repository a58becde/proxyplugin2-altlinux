#!/bin/bash
# ---------------------------------------------------------------------------
# Раскладка и снятие расширения Firefox.
#
# Единственный источник правды: вызывается и из install.sh/uninstall.sh, и из
# плейбуков Ansible (модулем ansible.builtin.script). Пока эта логика жила в
# двух местах, версии разошлись — sh читала profiles.ini, а Ansible работал по
# маске имени каталога, и часть профилей оставалась без расширения.
#
#   firewyrm-firefox-xpi.sh install <id> <файл.xpi>
#   firewyrm-firefox-xpi.sh remove  <id>
#   firewyrm-firefox-xpi.sh list    <id>
#
# Печатает по одному пути на строку: что установлено, снято или найдено.
#
# Переменные окружения (для тестов и установки в образ):
#   FW_USER_DIRS     каталоги пользователей, по умолчанию /home/*/ /home/*/*/ /root/
#   FW_FIREFOX_DIRS  каталоги установки Firefox
# ---------------------------------------------------------------------------

set -uo pipefail

action="${1:-}"
xpi_id="${2:-}"
src="${3:-}"

case "$action" in
    install) [ -n "$xpi_id" ] && [ -f "$src" ] || { echo "usage: $0 install <id> <xpi>" >&2; exit 2; } ;;
    remove|list) [ -n "$xpi_id" ] || { echo "usage: $0 $action <id>" >&2; exit 2; } ;;
    *) echo "usage: $0 <install|remove|list> <id> [xpi]" >&2; exit 2 ;;
esac

# shellcheck disable=SC2206
user_dirs=(${FW_USER_DIRS:-/home/*/ /home/*/*/ /root/})
# shellcheck disable=SC2206
firefox_dirs=(${FW_FIREFOX_DIRS:-/usr/lib64/firefox /usr/lib/firefox /usr/lib64/firefox-esr /usr/lib/firefox-esr})

# Профили так, как их видит сам Firefox: список в profiles.ini. Маска по имени
# (*.default*) — запасной вариант, имя каталога профиля произвольное.
profiles_from_ini() {
    local ffdir="${1%/}" ini="${1%/}/profiles.ini" path
    [ -f "$ini" ] || return 0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            /*) [ -d "$path" ] && printf '%s/\n' "${path%/}" ;;
            *)  [ -d "${ffdir}/${path}" ] && printf '%s/%s/\n' "$ffdir" "${path%/}" ;;
        esac
    done < <(sed -n 's/^[[:space:]]*Path[[:space:]]*=[[:space:]]*//p' "$ini" | tr -d '\r')
}

# profiles_by_glob <каталог firefox> [default]
# С аргументом default отбираются только каталоги, в имени которых есть
# ".default" — фильтровать надо по имени профиля, а не по всему пути: домашний
# каталог пользователя тоже может содержать эту подстроку.
profiles_by_glob() {
    local ffdir="${1%/}" only="${2:-}" path base
    for path in "$ffdir"/*/; do
        [ -d "$path" ] || continue
        base="${path%/}"; base="${base##*/}"
        if [ "$only" = default ]; then
            case "$base" in *.default*) ;; *) continue ;; esac
        fi
        printf '%s\n' "$path"
    done
}

# Куда ставим: только профили из profiles.ini (а если его нет — по маске).
install_targets() {
    local dir ffdir found
    for dir in "${user_dirs[@]}"; do
        ffdir="${dir%/}/.mozilla/firefox"
        [ -d "$ffdir" ] || continue
        found=$(profiles_from_ini "$ffdir")
        if [ -n "$found" ]; then
            printf '%s\n' "$found"
        else
            profiles_by_glob "$ffdir" default
        fi
    done
}

# Где искать при удалении: шире, чем ставим. Firefox, подхватив xpi из
# distribution/extensions, заводит копию в активном профиле, а он может быть
# не указан в profiles.ini или называться как угодно.
search_dirs() {
    local dir ffdir
    for dir in "${user_dirs[@]}"; do
        ffdir="${dir%/}/.mozilla/firefox"
        [ -d "$ffdir" ] || continue
        profiles_from_ini "$ffdir"
        profiles_by_glob "$ffdir"
    done
}

case "$action" in
install)
    while IFS= read -r prof; do
        [ -n "$prof" ] || continue
        dir="${prof}extensions"
        # Каталог профиля чужой: создаём extensions, только если его нет, и не
        # трогаем права существующего.
        if ! { [ -d "$dir" ] || mkdir -p "$dir"; }; then
            echo "WARN: не удалось создать $dir" >&2
            continue
        fi
        if ! cp -f -- "$src" "${dir}/${xpi_id}.xpi"; then
            echo "WARN: не удалось записать ${dir}/${xpi_id}.xpi" >&2
            continue
        fi
        chmod 0644 "${dir}/${xpi_id}.xpi"
        # Владелец — владелец профиля, а не root: иначе Firefox под
        # пользователем не сможет управлять расширением.
        chown --reference="${prof%/}" "${dir}/${xpi_id}.xpi" "$dir" 2>/dev/null \
            || echo "WARN: не удалось выставить владельца ${dir}" >&2
        printf '%s\n' "${dir}/${xpi_id}.xpi"
    done < <(install_targets | sort -u)

    for d in "${firefox_dirs[@]}"; do
        [ -d "$d" ] || continue
        if ! mkdir -p "$d/distribution/extensions"; then
            echo "WARN: не удалось создать $d/distribution/extensions" >&2
            continue
        fi
        if ! cp -f -- "$src" "$d/distribution/extensions/${xpi_id}.xpi"; then
            echo "WARN: не удалось записать $d/distribution/extensions/${xpi_id}.xpi" >&2
            continue
        fi
        chmod 0644 "$d/distribution/extensions/${xpi_id}.xpi"
        printf '%s\n' "$d/distribution/extensions/${xpi_id}.xpi"
    done
    ;;

remove|list)
    while IFS= read -r prof; do
        [ -n "$prof" ] || continue
        f="${prof}extensions/${xpi_id}.xpi"
        [ -e "$f" ] || continue
        [ "$action" = remove ] && { rm -f -- "$f" || continue; }
        printf '%s\n' "$f"
    done < <(search_dirs | sort -u)

    for d in "${firefox_dirs[@]}"; do
        f="$d/distribution/extensions/${xpi_id}.xpi"
        [ -e "$f" ] || continue
        [ "$action" = remove ] && { rm -f -- "$f" || continue; }
        printf '%s\n' "$f"
    done
    ;;
esac
exit 0
