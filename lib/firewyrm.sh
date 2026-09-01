#!/bin/bash
# ---------------------------------------------------------------------------
# Общие параметры и функции установки/удаления FireWyrm (СЭДД).
# Подключается через "." из install.sh и uninstall.sh, самостоятельно не
# запускается.
#
# Все значения переопределяются переменными окружения, например:
#   FW_PREFIX=/opt/sedd ./install.sh
# ---------------------------------------------------------------------------

FW_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# --- Параметры установки ---------------------------------------------------

# Префикс всей файловой иерархии. Пустой на рабочей машине; задаётся при
# установке в chroot/образ и в test.sh.
FW_SYSROOT="${FW_SYSROOT:-}"

FW_PREFIX="${FW_PREFIX:-${FW_SYSROOT}/opt/firewyrm}"
FW_BIN_DIR="${FW_BIN_DIR:-${FW_PREFIX}/bin}"

FW_HOST="${FW_HOST:-ru.intertrust.firewyrmhost}"      # имя native messaging host
FW_HOST_BIN="${FW_HOST_BIN:-FireWyrmNativeMessageHost}"
FW_PLUGIN_SO="${FW_PLUGIN_SO:-npProxyPlugin2.so}"

# Расширение Firefox — подписанная сборка из firefox-extension/.
# FW_XPI_ID обязан совпадать с browser_specific_settings.gecko.id: по нему
# именуется файл в каталоге extensions (иначе Firefox его игнорирует) и по нему
# же хост пускает расширение (allowed_extensions).
FW_XPI="${FW_XPI:-proxyplugin2-firefox.xpi}"
FW_XPI_ID="${FW_XPI_ID:-{aa17458a-0172-46a5-a961-f8028a5883d2}}"

FW_EXT_ID="${FW_EXT_ID:-dpkefahlefbmfgfgfoppbpkacgdmadpp}"
FW_EXT_UPDATE_URL="${FW_EXT_UPDATE_URL:-https://clients2.google.com/service/update2/crx}"
FW_EXT_SOURCE="${FW_EXT_SOURCE:-https://sedd.nso.ru/*}"
FW_POLICY_NAME="${FW_POLICY_NAME:-firewyrm.json}"     # свой файл, чужие политики не трогаем

FW_PACKAGE="${FW_PACKAGE:-chromium}"                  # пакет браузера (ALT Linux)

# --- Каталоги NPAPI-плагинов -----------------------------------------------
# FireWyrmNativeMessageHost сканирует эти пути (зашиты в бинарнике):
#   $HOME/.mozilla/plugins, /usr/lib/mozilla/plugins, /usr/lib64/mozilla/plugins
# и подгружает оттуда библиотеки, экспортирующие FireWyrm_Init.
# Ставим общесистемно, чтобы плагин работал для всех пользователей.

FW_NPAPI_DIRS=("${FW_SYSROOT}/usr/lib64/mozilla/plugins" "${FW_SYSROOT}/usr/lib/mozilla/plugins")

if [ -z "${FW_NPAPI_DIR:-}" ]; then
    if [ -d "${FW_SYSROOT}/usr/lib64" ] || [ -n "${FW_SYSROOT}" ]; then
        FW_NPAPI_DIR="${FW_SYSROOT}/usr/lib64/mozilla/plugins"
    else
        FW_NPAPI_DIR="${FW_SYSROOT}/usr/lib/mozilla/plugins"
    fi
fi

# Каталоги установки Firefox: туда кладётся distribution/extensions —
# оттуда расширение попадает во вновь создаваемые профили.
FW_FIREFOX_DIRS=(
    "${FW_SYSROOT}/usr/lib64/firefox"
    "${FW_SYSROOT}/usr/lib/firefox"
    "${FW_SYSROOT}/usr/lib64/firefox-esr"
    "${FW_SYSROOT}/usr/lib/firefox-esr"
)

# Манифесты native messaging для Firefox. Формат отличается от Chromium:
# ключ allowed_extensions с id расширения вместо allowed_origins.
FW_FF_NM_DIRS=(
    "${FW_SYSROOT}/usr/lib64/mozilla/native-messaging-hosts"
    "${FW_SYSROOT}/usr/lib/mozilla/native-messaging-hosts"
)
FW_FF_NM_DIR="${FW_NPAPI_DIR%/plugins}/native-messaging-hosts"

# Политика Firefox. В отличие от Chromium здесь один общий файл на все
# политики, своего рядом не положить — поэтому правим слиянием, чужие ключи
# не трогаем. Без политики расширение из каталога профиля активируется только
# со второго запуска браузера: первый старт его лишь регистрирует.
FW_FF_POLICY="${FW_FF_POLICY:-${FW_SYSROOT}/etc/firefox/policies/policies.json}"

# --- Общесистемные каталоги браузеров --------------------------------------
# Манифесты native messaging. Общесистемные каталоги работают для всех
# пользователей, поэтому домашние каталоги (и имя пользователя) знать не нужно.
# Набор браузеров — как в исходном установщике вендора, приоритет chromium.

FW_NM_DIRS=(
    "${FW_SYSROOT}/etc/chromium/native-messaging-hosts"                 # chromium (ALT Linux)
    "${FW_SYSROOT}/etc/chromium-browser/native-messaging-hosts"         # chromium (сборки Debian-типа)
    "${FW_SYSROOT}/etc/chromium-gost/native-messaging-hosts"            # chromium-gost
    "${FW_SYSROOT}/etc/opt/chrome/native-messaging-hosts"               # google-chrome
    "${FW_SYSROOT}/etc/opt/yandex/browser/native-messaging-hosts"       # yandex-browser
    "${FW_SYSROOT}/etc/opt/yandex/browser-beta/native-messaging-hosts"  # yandex-browser-beta
)

# Управляемые политики (принудительная установка расширения).
FW_POLICY_DIRS=(
    "${FW_SYSROOT}/etc/chromium/policies/managed"
    "${FW_SYSROOT}/etc/chromium-browser/policies/managed"
    "${FW_SYSROOT}/etc/chromium-gost/policies/managed"
    "${FW_SYSROOT}/etc/opt/chrome/policies/managed"
    "${FW_SYSROOT}/etc/opt/yandex/browser/policies/managed"
    "${FW_SYSROOT}/etc/opt/yandex/browser-beta/policies/managed"
)

# Старые пользовательские копии (их ставил прежний установщик): пользовательский
# манифест перекрывает общесистемный, поэтому его нужно убрать.
# Каталоги пользователей: обычные /home/<user>, доменные /home/<DOMAIN>/<user>
# и /root. Рекурсивный обход /home не используется — он на доменных профилях
# уходит в кэши браузера и работает минутами, а нужные пути известны точно.
# shellcheck disable=SC2206
FW_USER_DIRS=(${FW_USER_DIRS:-/home/*/ /home/*/*/ /root/})

# Пути внутри домашнего каталога (шаблоны раскрываются глоббингом).
FW_STALE_PATHS=(
    ".config/*/NativeMessagingHosts/${FW_HOST}.json"
    ".mozilla/native-messaging-hosts/${FW_HOST}.json"
    ".mozilla/plugins/${FW_PLUGIN_SO}"
    ".mozilla/plugins/${FW_HOST_BIN}"
)

# --- Вывод -----------------------------------------------------------------

fw_head() { printf '\n== %s ==\n' "$*"; }
fw_ok()   { printf '  [ OK ] %s\n' "$*"; }
fw_info() { printf '  [ .. ] %s\n' "$*"; }
fw_warn() { printf '  [ !! ] %s\n' "$*" >&2; }
fw_die()  { printf '\nОШИБКА: %s\n' "$*" >&2; exit 1; }

# --- Проверки --------------------------------------------------------------

# В ALT Linux нет sudo — работаем только от root, вход через "su -".
fw_require_root() {
    [ "$(id -u)" -eq 0 ] || fw_die "нужны права root. Выполните:
    su -
    $1"
}

# --- Генерация конфигураций ------------------------------------------------

fw_manifest_json() {
    cat <<JSON
{
   "name": "${FW_HOST}",
   "description": "FireBreath FireWyrm Native Messaging Wyrmhole",
   "path": "${FW_BIN_DIR}/${FW_HOST_BIN}",
   "type": "stdio",
   "allowed_origins": ["chrome-extension://${FW_EXT_ID}/"]
}
JSON
}

fw_ff_manifest_json() {
    cat <<JSON
{
   "name": "${FW_HOST}",
   "description": "FireBreath FireWyrm Native Messaging Wyrmhole",
   "path": "${FW_BIN_DIR}/${FW_HOST_BIN}",
   "type": "stdio",
   "allowed_extensions": ["${FW_XPI_ID}"]
}
JSON
}

# fw_ff_policy <add|remove|purge>
#
#   add     force_installed — расширение ставится и удерживается
#   remove  blocked — Firefox СНИМАЕТ расширение при следующем запуске
#   purge   запись удаляется совсем
#
# Именно blocked, а не удаление записи: убрать force_installed означает лишь
# «больше не удерживать принудительно» — Firefox снимает замочек, а само
# расширение остаётся установленным, потому что оно уже в его базе и файл на
# диске ему больше не нужен. Запись blocked снимается позже, командой purge,
# когда все машины перезапустили браузер.
fw_ff_policy() {
    local action="$1" tmp
    command -v python3 >/dev/null 2>&1 || {
        fw_warn "нет python3 — политика Firefox не настроена, потребуется два запуска браузера"
        return 0
    }
    if [ "$action" = add ] && ! install -d -m 0755 -- "${FW_FF_POLICY%/*}"; then
        fw_warn "не удалось создать ${FW_FF_POLICY%/*} — политика Firefox не настроена"
        return 0
    fi
    [ -d "${FW_FF_POLICY%/*}" ] || return 0

    # В install_url путь должен быть таким, каким его увидит браузер на целевой
    # системе: префикс образа (FW_SYSROOT) в него попадать не должен.
    tmp="${FW_FF_POLICY}.fw-tmp"
    rm -f -- "$tmp"    # от прерванного запуска мог остаться чужой tmp
    if python3 - "$FW_FF_POLICY" "$tmp" "$action" "$FW_XPI_ID" \
                 "file://${FW_PREFIX#"$FW_SYSROOT"}/${FW_XPI}" <<'PYFF'
import json, os, sys
src, tmp, action, ext_id, url = sys.argv[1:6]
try:
    with open(src) as f:
        doc = json.load(f)
except (IOError, OSError):
    doc = {}
except ValueError:
    sys.exit('policies.json повреждён, разберитесь вручную')
if not isinstance(doc, dict):
    sys.exit('policies.json имеет неожиданный формат')

pol = doc.setdefault('policies', {})
ext = pol.setdefault('ExtensionSettings', {})

if action == 'add':
    ext[ext_id] = {'installation_mode': 'force_installed', 'install_url': url}
elif action == 'remove':
    ext[ext_id] = {'installation_mode': 'blocked'}
else:
    ext.pop(ext_id, None)
    if not ext:
        pol.pop('ExtensionSettings', None)

if action == 'purge' and not pol:
    # Файл наш и больше в нём ничего нет — убираем целиком.
    sys.exit(0)

with open(tmp, 'w') as f:
    json.dump(doc, f, indent=2, ensure_ascii=False)
    f.write('\n')
PYFF
    then
        if [ -f "$tmp" ]; then
            chmod 0644 "$tmp" && mv -f "$tmp" "$FW_FF_POLICY"
            fw_ok "$FW_FF_POLICY"
        else
            fw_rm "$FW_FF_POLICY"
        fi
    else
        rm -f "$tmp"
        fw_warn "не удалось изменить $FW_FF_POLICY"
        fw_info "если файл защищён от записи: chattr -i $FW_FF_POLICY"
    fi
    return 0
}

# Режим нашей записи в политике Firefox: force_installed, blocked или пусто.
# Именно нашей: grep по файлу находил бы и чужие записи с тем же словом.
fw_ff_policy_mode() {
    command -v python3 >/dev/null 2>&1 || return 0
    python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
e = d.get("policies", {}).get("ExtensionSettings", {}).get(sys.argv[2], {})
print(e.get("installation_mode", ""))
' "$FW_FF_POLICY" "$FW_XPI_ID" 2>/dev/null
}

fw_policy_json() {
    cat <<JSON
{
  "ExtensionInstallForcelist": [
    "${FW_EXT_ID};${FW_EXT_UPDATE_URL}"
  ],
  "ExtensionInstallSources": [
    "${FW_EXT_SOURCE}"
  ]
}
JSON
}

# --- Файловые операции -----------------------------------------------------

# fw_install <права> <откуда> <куда>
fw_install() {
    install -d -m 0755 -- "${3%/*}"
    install -m "$1" -- "$2" "$3"
    chown root:root "$3" 2>/dev/null || true
}

# fw_write <права> <файл>   -- содержимое читается со stdin
fw_write() {
    local mode="$1" dst="$2"
    install -d -m 0755 -- "${dst%/*}"
    cat > "$dst"
    chmod "$mode" "$dst"
    chown root:root "$dst" 2>/dev/null || true
}

# Удалить файл, если он есть, и сообщить об этом.
fw_rm() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        rm -rf -- "$path"
        fw_ok "удалено: $path"
    else
        fw_info "нет (пропуск): $path"
    fi
}

# Удалить каталог, если он пуст.
fw_rmdir_if_empty() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    rmdir -- "$dir" 2>/dev/null && fw_ok "удалён пустой каталог: $dir"
    return 0
}

# Старые пользовательские копии из ~/.config/*/NativeMessagingHosts и
# ~/.mozilla/plugins. Общесистемная установка их заменяет, а пользовательский
# манифест имеет приоритет — поэтому чистим и при установке, и при удалении.
fw_clean_user_leftovers() {
    local dir rel path found=0
    for dir in "${FW_USER_DIRS[@]}"; do
        dir="${dir%/}"
        for rel in "${FW_STALE_PATHS[@]}"; do
            # $rel без кавычек: нужен глоббинг по имени браузера в .config/*
            for path in "${dir}"/$rel; do
                [ -e "$path" ] || [ -L "$path" ] || continue
                rm -f -- "$path" && fw_ok "удалена пользовательская копия: $path"
                found=1
            done
        done
        # Ссылка ~/.mozilla/plugins -> /opt/..., её делал прежний установщик.
        path="${dir}/.mozilla/plugins"
        if [ -L "$path" ]; then
            rm -f -- "$path" && fw_ok "удалена устаревшая ссылка: $path"
            found=1
        fi
    done
    [ "$found" -eq 1 ] || fw_info "пользовательских копий не найдено"
}

# --- Расширение Firefox ----------------------------------------------------

# Вся работа с профилями Firefox — в отдельном скрипте, который вызывают и
# эти функции, и плейбуки Ansible. Логика одна на оба способа установки.
FW_XPI_SCRIPT="${FW_LIB_DIR}/firewyrm-firefox-xpi.sh"

# Запускаем через bash, а не напрямую: домашние каталоги (особенно доменные)
# часто смонтированы с noexec, и тогда файл со всеми правами на исполнение
# запустить нельзя, а test -x на нём возвращает ложь. Чтение при этом работает.
fw_xpi_run() {   # <install|remove|list> [аргументы]
    if [ ! -f "${FW_XPI_SCRIPT}" ] || [ ! -r "${FW_XPI_SCRIPT}" ]; then
        fw_warn "нет вспомогательного скрипта ${FW_XPI_SCRIPT}"
        return 1
    fi
    FW_USER_DIRS="${FW_USER_DIRS[*]}" FW_FIREFOX_DIRS="${FW_FIREFOX_DIRS[*]}" \
        bash "${FW_XPI_SCRIPT}" "$@"
}

# Жёсткая проверка — отдельно и до работы: fw_xpi_run вызывается внутри
# подстановки процесса, где exit убил бы только подоболочку, а скрипт продолжил
# бы работу как ни в чём не бывало.
fw_xpi_require() {
    [ -f "${FW_XPI_SCRIPT}" ] && [ -r "${FW_XPI_SCRIPT}" ] || fw_die \
"нет вспомогательного скрипта ${FW_XPI_SCRIPT} — в нём вся работа с профилями Firefox.
Копируйте каталог lib/ целиком, а не только firewyrm.sh."
}

# Проверка файла расширения до установки. Два отказа тихие и потому опасные:
# при несовпадении id файл ляжет под чужим именем и не совпадёт с
# allowed_extensions, а неподписанный xpi Firefox просто игнорирует — в обоих
# случаях ошибки нигде не видно, расширения просто нет.
fw_xpi_check() {
    local file="$1" info id state
    if ! command -v python3 >/dev/null 2>&1; then
        fw_info "нет python3 — проверка xpi пропущена"
        return 0
    fi
    info=$(python3 -c '
import json, sys, zipfile
try:
    z = zipfile.ZipFile(sys.argv[1])
    m = json.loads(z.read("manifest.json"))
    i = m.get("browser_specific_settings", {}).get("gecko", {}).get("id", "")
    signed = any(n.startswith("META-INF/") for n in z.namelist())
    print("%s|%s" % (i, "signed" if signed else "unsigned"))
except Exception:
    print("|broken")
' "$file" 2>/dev/null)

    id=${info%%|*}
    state=${info##*|}

    [ "$state" = "broken" ] && fw_die "не читается как расширение: $file"

    if [ "$id" != "${FW_XPI_ID}" ]; then
        fw_die "id расширения в $file не совпадает с настройкой:
    в файле:    ${id:-<нет>}
    ожидается:  ${FW_XPI_ID}
Этот же id задаёт имя файла в профиле и allowed_extensions в манифесте хоста.
Не совпадут — расширение молча не заработает. Поправьте FW_XPI_ID
(и fw_xpi_id в ansible/firewyrm_vars.yml) либо пересоберите xpi."
    fi
    fw_ok "id совпадает: ${id}"

    if [ "$state" = "signed" ]; then
        fw_ok "подпись на месте"
    else
        fw_warn "xpi НЕ ПОДПИСАН — Firefox его проигнорирует"
        fw_info "подпишите на addons.mozilla.org (Submit -> On your own)"
        fw_info "или снимите проверку подписей, если сборка ESR (см. README)"
    fi
    return 0
}

fw_install_xpi() {
    local src="$1" target found=0
    while IFS= read -r target; do
        fw_ok "$target"
        found=1
    done < <(fw_xpi_run install "${FW_XPI_ID}" "$src")
    [ "$found" -eq 1 ] || fw_info "профили Firefox и каталоги установки не найдены"
}

# --- Проверка установки ----------------------------------------------------
# Возвращает 0, если всё на месте. Используется и в install.sh --check.

fw_verify() {
    local errors=0 dir file

    if [ -x "${FW_BIN_DIR}/${FW_HOST_BIN}" ]; then
        fw_ok "${FW_BIN_DIR}/${FW_HOST_BIN}"
    else
        fw_warn "нет исполняемого файла ${FW_BIN_DIR}/${FW_HOST_BIN}"
        errors=$((errors + 1))
    fi

    if [ -f "${FW_NPAPI_DIR}/${FW_PLUGIN_SO}" ]; then
        fw_ok "${FW_NPAPI_DIR}/${FW_PLUGIN_SO}"
    else
        fw_warn "нет плагина ${FW_NPAPI_DIR}/${FW_PLUGIN_SO}"
        errors=$((errors + 1))
    fi

    for dir in "${FW_NM_DIRS[@]}"; do
        file="${dir}/${FW_HOST}.json"
        if ! [ -f "$file" ]; then
            fw_warn "нет манифеста $file"
            errors=$((errors + 1))
        elif ! grep -q "\"${FW_BIN_DIR}/${FW_HOST_BIN}\"" "$file"; then
            fw_warn "в $file неверный путь к ${FW_HOST_BIN}"
            errors=$((errors + 1))
        elif ! fw_json_valid "$file"; then
            fw_warn "$file — некорректный JSON"
            errors=$((errors + 1))
        else
            fw_ok "$file"
        fi
    done

    file="${FW_FF_NM_DIR}/${FW_HOST}.json"
    if ! [ -f "$file" ]; then
        fw_warn "нет манифеста Firefox $file"
        errors=$((errors + 1))
    elif ! grep -q "\"${FW_XPI_ID}\"" "$file"; then
        fw_warn "в $file allowed_extensions не совпадает с ${FW_XPI_ID}"
        errors=$((errors + 1))
    elif ! fw_json_valid "$file"; then
        fw_warn "$file — некорректный JSON"
        errors=$((errors + 1))
    else
        fw_ok "$file"
    fi

    # Расширение Firefox необязательно: пока нет подписанной сборки, его просто
    # не ставят. Копии в профилях — справочно: профиль мог появиться уже после
    # установки, и Firefox возьмёт расширение из distribution/extensions.
    if [ -f "${FW_PREFIX}/${FW_XPI}" ]; then
        fw_ok "${FW_PREFIX}/${FW_XPI}"
        for dir in "${FW_FIREFOX_DIRS[@]}"; do
            [ -d "$dir" ] || continue
            file="${dir}/distribution/extensions/${FW_XPI_ID}.xpi"
            if [ -f "$file" ]; then
                fw_ok "$file"
            else
                fw_warn "нет расширения $file"
                errors=$((errors + 1))
            fi
        done
        while IFS= read -r file; do
            fw_ok "$file"
        done < <(fw_xpi_run list "${FW_XPI_ID}" | grep -v '/distribution/extensions/' || true)

        if ! command -v python3 >/dev/null 2>&1; then
            fw_info "нет python3 — политика Firefox не проверяется"
        elif [ "$(fw_ff_policy_mode)" = force_installed ]; then
            fw_ok "${FW_FF_POLICY}"
        else
            fw_warn "в ${FW_FF_POLICY} нет установки расширения (force_installed)"
            errors=$((errors + 1))
        fi
    else
        fw_info "${FW_XPI} не установлен (Firefox пропущен)"
        if [ "$(fw_ff_policy_mode)" = force_installed ]; then
            fw_warn "в ${FW_FF_POLICY} осталась установка ${FW_XPI_ID}"
            errors=$((errors + 1))
        fi
        # Эталона нет, а копии есть — значит удаление отработало не до конца.
        while IFS= read -r file; do
            fw_warn "остался файл расширения: $file"
            errors=$((errors + 1))
        done < <(fw_xpi_run list "${FW_XPI_ID}")
    fi

    for dir in "${FW_POLICY_DIRS[@]}"; do
        file="${dir}/${FW_POLICY_NAME}"
        if ! [ -f "$file" ]; then
            fw_warn "нет политики $file"
            errors=$((errors + 1))
        elif ! grep -q "${FW_EXT_ID}" "$file"; then
            fw_warn "в $file нет id расширения ${FW_EXT_ID}"
            errors=$((errors + 1))
        elif ! fw_json_valid "$file"; then
            fw_warn "$file — некорректный JSON (браузер молча его проигнорирует)"
            errors=$((errors + 1))
        else
            fw_ok "$file"
        fi
    done

    return $((errors == 0 ? 0 : 1))
}

# Браузер молча игнорирует битый JSON политик, поэтому проверяем синтаксис.
fw_json_valid() {
    command -v python3 >/dev/null 2>&1 || return 0
    python3 -m json.tool "$1" >/dev/null 2>&1
}
