#!/bin/bash
# ---------------------------------------------------------------------------
# Установка FireWyrm (СЭДД) — вариант без Ansible.
#
# В ALT Linux нет sudo, поэтому запуск только от root:
#     su -
#     /путь/к/install.sh
#
# Ключи:
#     --check   только проверить текущую установку, ничего не менять
#
# Переменные окружения (см. lib/firewyrm.sh), например:
#     FW_SRC=/mnt/flash/sedd ./install.sh
# ---------------------------------------------------------------------------

set -euo pipefail

FW_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "${FW_ROOT}/lib/firewyrm.sh"

# Каталог с дистрибутивом определяется относительно самого скрипта.
FW_SRC="${FW_SRC:-${FW_ROOT}/sedd}"

if [ "${1:-}" = "--check" ]; then
    fw_head "Проверка установки FireWyrm"
    fw_verify && { printf '\nВсё на месте.\n'; exit 0; }
    printf '\nЕсть замечания — см. выше.\n'
    exit 1
fi

# При установке в chroot/образ (FW_SYSROOT) root и пакеты не нужны.
[ -n "${FW_SYSROOT}" ] || fw_require_root "${BASH_SOURCE[0]}"

printf '==========================================\n'
printf '  Установка FireWyrm (СЭДД)\n'
printf '==========================================\n'
printf '  дистрибутив: %s\n' "${FW_SRC}"
printf '  каталог:     %s\n' "${FW_PREFIX}"
printf '  плагин:      %s\n' "${FW_NPAPI_DIR}"

# --- 1. Проверка дистрибутива ----------------------------------------------

fw_head "Проверка исходных файлов"
for file in "${FW_HOST_BIN}" "${FW_PLUGIN_SO}"; do
    [ -f "${FW_SRC}/${file}" ] || fw_die "нет файла ${FW_SRC}/${file}
Укажите каталог с дистрибутивом: FW_SRC=/путь/к/sedd ${BASH_SOURCE[0]}"
    fw_ok "${file}"
done

# --- 2. Браузер -------------------------------------------------------------

fw_head "Браузер ${FW_PACKAGE}"
if [ -n "${FW_SYSROOT}" ]; then
    fw_info "установка в ${FW_SYSROOT} — пакеты не трогаем"
elif command -v "${FW_PACKAGE}" >/dev/null 2>&1; then
    fw_ok "уже установлен: $(command -v "${FW_PACKAGE}")"
else
    fw_info "не найден, устанавливаем из репозитория"
    apt-get update || fw_die "apt-get update завершился с ошибкой — проверьте репозитории и сеть"
    apt-get install -y "${FW_PACKAGE}" || fw_die "не удалось установить пакет ${FW_PACKAGE}"
    command -v "${FW_PACKAGE}" >/dev/null 2>&1 \
        || fw_die "пакет ${FW_PACKAGE} установлен, но исполняемый файл не найден"
    fw_ok "установлен: $(command -v "${FW_PACKAGE}")"
fi

# --- 3. Native messaging host ----------------------------------------------

fw_head "Установка ${FW_HOST_BIN}"
fw_install 0755 "${FW_SRC}/${FW_HOST_BIN}" "${FW_BIN_DIR}/${FW_HOST_BIN}"
fw_ok "${FW_BIN_DIR}/${FW_HOST_BIN}"

# --- 4. Плагин --------------------------------------------------------------
# Каталог сканирует сам хост, см. комментарий в lib/firewyrm.sh.

fw_head "Установка ${FW_PLUGIN_SO}"
fw_install 0644 "${FW_SRC}/${FW_PLUGIN_SO}" "${FW_NPAPI_DIR}/${FW_PLUGIN_SO}"
fw_ok "${FW_NPAPI_DIR}/${FW_PLUGIN_SO}"

# --- 5. Расширение Firefox --------------------------------------------------

fw_head "Манифест native messaging для Firefox"
fw_ff_manifest_json | fw_write 0644 "${FW_FF_NM_DIR}/${FW_HOST}.json"
fw_ok "${FW_FF_NM_DIR}/${FW_HOST}.json"

# Подписанной сборки может ещё не быть — Chromium от этого не страдает.
fw_head "Установка ${FW_XPI}"
if [ -f "${FW_SRC}/${FW_XPI}" ]; then
    fw_xpi_check "${FW_SRC}/${FW_XPI}"
    fw_install 0644 "${FW_SRC}/${FW_XPI}" "${FW_PREFIX}/${FW_XPI}"
    fw_ok "${FW_PREFIX}/${FW_XPI}"
    fw_install_xpi "${FW_PREFIX}/${FW_XPI}"
    # Без политики расширение активируется только со второго запуска браузера.
    fw_head "Политика Firefox"
    fw_ff_policy add
else
    fw_warn "нет ${FW_SRC}/${FW_XPI} — Firefox пропущен, Chromium установлен"
    fw_info "соберите firefox-extension/build.sh, подпишите и положите файл сюда"
fi

# --- 6. Манифесты браузеров -------------------------------------------------

fw_head "Манифесты native messaging"
for dir in "${FW_NM_DIRS[@]}"; do
    fw_manifest_json | fw_write 0644 "${dir}/${FW_HOST}.json"
    fw_ok "${dir}/${FW_HOST}.json"
done

# --- 7. Политики: принудительная установка расширения -----------------------

fw_head "Политики (расширение ${FW_EXT_ID})"
for dir in "${FW_POLICY_DIRS[@]}"; do
    fw_policy_json | fw_write 0644 "${dir}/${FW_POLICY_NAME}"
    fw_ok "${dir}/${FW_POLICY_NAME}"
done

# --- 8. Старые пользовательские копии ---------------------------------------

fw_head "Очистка старых пользовательских копий"
fw_clean_user_leftovers

# --- 9. Проверка ------------------------------------------------------------

fw_head "Проверка установки"
if fw_verify; then
    status="УСТАНОВКА ЗАВЕРШЕНА"
else
    status="УСТАНОВКА ЗАВЕРШЕНА С ЗАМЕЧАНИЯМИ (см. выше)"
fi

cat <<TXT

==========================================
  ${status}
==========================================

Дальше:
  1. Полностью закройте браузер ${FW_PACKAGE} (все окна).
  2. Запустите его снова — расширение ${FW_EXT_ID}
     установится политикой автоматически.
  3. Проверьте chrome://policy и chrome://extensions
  4. Откройте ${FW_EXT_SOURCE%/\*}/

Проверить установку повторно:  ${BASH_SOURCE[0]} --check
Удалить:                       ${FW_ROOT}/uninstall.sh
TXT
