#!/bin/bash
# ---------------------------------------------------------------------------
# Удаление FireWyrm (СЭДД) — вариант без Ansible.
#
# В ALT Linux нет sudo, поэтому запуск только от root:
#     su -
#     /путь/к/uninstall.sh
#
# Ключи:
#     -y, --yes   не спрашивать подтверждение
# ---------------------------------------------------------------------------

set -euo pipefail

FW_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "${FW_ROOT}/lib/firewyrm.sh"

# При удалении из chroot/образа (FW_SYSROOT) root не нужен.
[ -n "${FW_SYSROOT}" ] || fw_require_root "${BASH_SOURCE[0]}"

printf '==========================================\n'
printf '  Удаление FireWyrm (СЭДД)\n'
printf '==========================================\n'
printf 'Будет удалено:\n'
printf '  - %s\n' "${FW_PREFIX}"
printf '  - %s\n' "${FW_NPAPI_DIRS[@]/%//${FW_PLUGIN_SO}}"
printf '  - расширение %s.xpi из профилей Firefox\n' "${FW_XPI_ID}"
printf '  - манифесты %s.json из каталогов браузеров\n' "${FW_HOST}"
printf '  - политики %s из каталогов браузеров\n' "${FW_POLICY_NAME}"
printf '  - пользовательские копии в ~/.config/*/NativeMessagingHosts и ~/.mozilla\n'
printf 'Браузер %s НЕ удаляется.\n\n' "${FW_PACKAGE}"

case "${1:-}" in
    -y|--yes) ;;
    *)
        read -r -p "Продолжить? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Отменено."; exit 0; }
        ;;
esac

fw_xpi_require

# --- 1. Процессы ------------------------------------------------------------

fw_head "Остановка процессов"
if pkill -f "${FW_HOST_BIN}" 2>/dev/null; then
    fw_ok "процессы ${FW_HOST_BIN} остановлены"
else
    fw_info "процессы ${FW_HOST_BIN} не найдены"
fi

# --- 2. Файлы ---------------------------------------------------------------

fw_head "Удаление файлов"
fw_rm "${FW_PREFIX}"
for dir in "${FW_NPAPI_DIRS[@]}"; do
    fw_rm "${dir}/${FW_PLUGIN_SO}"
done

fw_head "Политика Firefox"
fw_ff_policy remove

fw_head "Удаление расширения Firefox"
removed=0
while IFS= read -r path; do
    fw_ok "удалено: $path"
    removed=1
done < <(fw_xpi_run remove "${FW_XPI_ID}")
[ "$removed" -eq 1 ] || fw_info "копий расширения не найдено"

fw_head "Удаление манифестов native messaging"
for dir in "${FW_FF_NM_DIRS[@]}"; do
    fw_rm "${dir}/${FW_HOST}.json"
done
for dir in "${FW_NM_DIRS[@]}"; do
    fw_rm "${dir}/${FW_HOST}.json"
    fw_rmdir_if_empty "${dir}"
done

fw_head "Удаление политик"
for dir in "${FW_POLICY_DIRS[@]}"; do
    fw_rm "${dir}/${FW_POLICY_NAME}"
    fw_rmdir_if_empty "${dir}"
done

fw_head "Удаление пользовательских копий"
fw_clean_user_leftovers

# --- 3. Проверка ------------------------------------------------------------

fw_head "Проверка"
remaining=0
for path in "${FW_PREFIX}" \
            "${FW_NPAPI_DIRS[@]/%//${FW_PLUGIN_SO}}" \
            "${FW_NM_DIRS[@]/%//${FW_HOST}.json}" \
            "${FW_FF_NM_DIRS[@]/%//${FW_HOST}.json}" \
            "${FW_POLICY_DIRS[@]/%//${FW_POLICY_NAME}}"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
        fw_warn "остался: $path"
        remaining=$((remaining + 1))
    fi
done

# Копии расширения и политика Firefox — то, что чаще всего и остаётся.
while IFS= read -r path; do
    fw_warn "остался: $path"
    remaining=$((remaining + 1))
done < <(fw_xpi_run list "${FW_XPI_ID}")

if [ "$(fw_ff_policy_mode)" = force_installed ]; then
    fw_warn "в ${FW_FF_POLICY} осталась установка расширения"
    remaining=$((remaining + 1))
fi

printf '\n==========================================\n'
if [ "$remaining" -eq 0 ]; then
    printf '  УДАЛЕНИЕ ЗАВЕРШЕНО\n'
else
    printf '  ОСТАЛОСЬ ОБЪЕКТОВ: %d (см. выше)\n' "$remaining"
fi
printf '==========================================\n\n'
printf 'Расширение удалится из браузеров после их перезапуска:\n'
printf '  Chromium — политика снята;\n'
printf '  Firefox  — политика переведена в blocked, он снимет расширение сам.\n'
printf 'Когда все машины перезапустили Firefox, запись можно убрать совсем:\n'
printf '  . %s/lib/firewyrm.sh && fw_ff_policy purge\n' "${FW_ROOT}"
printf 'Переустановка: %s/install.sh\n' "${FW_ROOT}"

[ "$remaining" -eq 0 ]
