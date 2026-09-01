#!/bin/bash
# ---------------------------------------------------------------------------
# Смоук-тест: установка во временный каталог, проверка, удаление.
# Ничего в системе не меняет, root не нужен:
#     ./test.sh
# ---------------------------------------------------------------------------

set -euo pipefail

FW_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf -- "$SANDBOX"' EXIT

export FW_SYSROOT="${SANDBOX}/sysroot"
export FW_USER_DIRS="${SANDBOX}/home/*/"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Имитируем старую установку исходным shell.sh: пользовательский манифест
# перекрывает общесистемный, установщик обязан его убрать.
STALE="${SANDBOX}/home/user/.config/chromium/NativeMessagingHosts"
mkdir -p "$STALE" "${SANDBOX}/home/user/.mozilla/plugins"
echo '{"path":"/old/broken/path"}' > "${STALE}/ru.intertrust.firewyrmhost.json"
touch "${SANDBOX}/home/user/.mozilla/plugins/npProxyPlugin2.so"
# ...и ссылку ~/.mozilla/plugins -> /opt/..., которую делал legacy-установщик
mkdir -p "${SANDBOX}/home/user2/.mozilla"
ln -s "${FW_SYSROOT}/opt/firewyrm/plugins" "${SANDBOX}/home/user2/.mozilla/plugins"

# Дистрибутив копируется в песочницу: тест не должен писать в sedd/ рабочего
# каталога — там лежит подписанный xpi, а тест бы его перезаписал и удалил.
export FW_SRC="${SANDBOX}/src"
mkdir -p "$FW_SRC"
cp "${FW_ROOT}/sedd/FireWyrmNativeMessageHost" \
   "${FW_ROOT}/sedd/npProxyPlugin2.so" "$FW_SRC/"
"${FW_ROOT}/firefox-extension/build.sh" > /dev/null
cp "${FW_ROOT}/proxyplugin2-firefox-UNSIGNED.xpi" "$FW_SRC/proxyplugin2-firefox.xpi"

# Профили Firefox: список берётся из profiles.ini, а не по маске имени.
# Один профиль назван так, что под *.default* не подходит вовсе.
FFDIR="${SANDBOX}/home/user/.mozilla/firefox"
PROFILE="${FFDIR}/r906vq7n.default-default"
PROFILE2="${FFDIR}/qq11ww22.work"
mkdir -p "$PROFILE" "$PROFILE2" "${FW_SYSROOT}/usr/lib64/firefox"
cat > "${FFDIR}/profiles.ini" <<INI
[Profile0]
Name=default
IsRelative=1
Path=r906vq7n.default-default

[Profile1]
Name=work
IsRelative=1
Path=qq11ww22.work
INI

# Чужая политика Firefox: слияние обязано её сохранить.
FFPOL="${FW_SYSROOT}/etc/firefox/policies/policies.json"
mkdir -p "$(dirname "$FFPOL")"
cat > "$FFPOL" <<POL
{"policies":{"DisableTelemetry":true,"ExtensionSettings":{"mis-watch@nokod.local":{"installation_mode":"force_installed","install_url":"file:///usr/lib/firefox/x.xpi"}}}}
POL

# --- Установка --------------------------------------------------------------

"${FW_ROOT}/install.sh" > "${SANDBOX}/install.log" 2>&1 \
    || { cat "${SANDBOX}/install.log"; fail "install.sh завершился с ошибкой"; }

[ -x "${FW_SYSROOT}/opt/firewyrm/bin/FireWyrmNativeMessageHost" ] \
    || fail "не установлен исполняемый файл"
[ -f "${FW_SYSROOT}/usr/lib64/mozilla/plugins/npProxyPlugin2.so" ] \
    || fail "не установлен npProxyPlugin2.so"

XPI_ID="{aa17458a-0172-46a5-a961-f8028a5883d2}"
[ -f "${PROFILE}/extensions/${XPI_ID}.xpi" ] \
    || fail "xpi не установлен в профиль Firefox"
[ -f "${PROFILE2}/extensions/${XPI_ID}.xpi" ] \
    || fail "xpi не установлен в профиль из profiles.ini с нестандартным именем"
[ -f "${FW_SYSROOT}/usr/lib64/firefox/distribution/extensions/${XPI_ID}.xpi" ] \
    || fail "xpi не установлен в distribution/extensions"
cmp -s "${FW_SRC}/proxyplugin2-firefox.xpi" "${PROFILE}/extensions/${XPI_ID}.xpi" \
    || fail "xpi в профиле отличается от исходного"

ffman="${FW_SYSROOT}/usr/lib64/mozilla/native-messaging-hosts/ru.intertrust.firewyrmhost.json"
[ -f "$ffman" ] || fail "нет манифеста native messaging для Firefox"
python3 -m json.tool "$ffman" > /dev/null || fail "манифест Firefox — не JSON"
grep -q "\"allowed_extensions\": \[\"${XPI_ID}\"\]" "$ffman" \
    || fail "в манифесте Firefox неверный allowed_extensions"

manifest="${FW_SYSROOT}/etc/chromium/native-messaging-hosts/ru.intertrust.firewyrmhost.json"
[ -f "$manifest" ] || fail "нет манифеста для chromium"
python3 -m json.tool "$manifest" > /dev/null || fail "манифест — не JSON"
grep -q "${FW_SYSROOT}/opt/firewyrm/bin/FireWyrmNativeMessageHost" "$manifest" \
    || fail "в манифесте неверный путь"
grep -q 'chrome-extension://dpkefahlefbmfgfgfoppbpkacgdmadpp/' "$manifest" \
    || fail "в манифесте неверный allowed_origins"

policy="${FW_SYSROOT}/etc/chromium/policies/managed/firewyrm.json"
[ -f "$policy" ] || fail "нет политики для chromium"
python3 -m json.tool "$policy" > /dev/null || fail "политика — не JSON"
python3 - "$policy" <<'PY' || fail "в политике неверные ключи"
import json, sys
p = json.load(open(sys.argv[1]))
assert p["ExtensionInstallForcelist"] == [
    "dpkefahlefbmfgfgfoppbpkacgdmadpp;https://clients2.google.com/service/update2/crx"], p
assert p["ExtensionInstallSources"] == ["https://sedd.nso.ru/*"], p
PY

[ -e "${STALE}/ru.intertrust.firewyrmhost.json" ] \
    && fail "старый пользовательский манифест не удалён"
[ -e "${SANDBOX}/home/user/.mozilla/plugins/npProxyPlugin2.so" ] \
    && fail "старый пользовательский плагин не удалён"
[ -L "${SANDBOX}/home/user2/.mozilla/plugins" ] \
    && fail "устаревшая ссылка ~/.mozilla/plugins не удалена"

python3 - "$FFPOL" "$XPI_ID" <<'PYPOL' || fail "слияние политики Firefox сломано"
import json, sys
d = json.load(open(sys.argv[1]))
p = d['policies']
assert p.get('DisableTelemetry') is True, 'чужой ключ политики потерян'
e = p['ExtensionSettings']
assert 'mis-watch@nokod.local' in e, 'чужое расширение выброшено из политики'
assert e[sys.argv[2]]['installation_mode'] == 'force_installed', e
PYPOL

"${FW_ROOT}/install.sh" --check > /dev/null || fail "--check не подтвердил установку"

# --check обязан замечать пропажу расширения из профиля
rm -f "${PROFILE}/extensions/${XPI_ID}.xpi"
"${FW_ROOT}/install.sh" --check > /dev/null 2>&1 && fail "--check не заметил пропажу xpi"
"${FW_ROOT}/install.sh" > /dev/null 2>&1 || fail "переустановка после пропажи xpi сломалась"
[ -f "${PROFILE}/extensions/${XPI_ID}.xpi" ] || fail "xpi не восстановлен переустановкой"

# Повторная установка должна проходить без ошибок (идемпотентность).
"${FW_ROOT}/install.sh" > /dev/null 2>&1 || fail "повторная установка сломалась"

# Копия в профиле, имя которого НЕ подходит под маску установки *.default*:
# так делает сам Firefox, подхватив xpi из distribution/extensions.
ODD="${SANDBOX}/home/user/.mozilla/firefox/zz9q1w2e.dev"
mkdir -p "${ODD}/extensions"
cp "${FW_SRC}/proxyplugin2-firefox.xpi" "${ODD}/extensions/${XPI_ID}.xpi"

# xpi с чужим id обязан ронять установку, а не ставиться молча под чужим именем
python3 - "${FW_SRC}/proxyplugin2-firefox.xpi" "${SANDBOX}/wrong-id.xpi" <<'PYEOF'
import json, shutil, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
zin = zipfile.ZipFile(src)
m = json.loads(zin.read('manifest.json'))
m['browser_specific_settings']['gecko']['id'] = 'someone-else@example.org'
with zipfile.ZipFile(dst, 'w') as zout:
    for n in zin.namelist():
        zout.writestr(n, json.dumps(m) if n == 'manifest.json' else zin.read(n))
PYEOF
cp "${SANDBOX}/wrong-id.xpi" "${FW_SRC}/proxyplugin2-firefox.xpi"
out=$("${FW_ROOT}/install.sh" 2>&1 || true)
case "$out" in
    *"не совпадает с настройкой"*) ;;
    *) fail "установка не заметила чужой id в xpi" ;;
esac
cp "${FW_ROOT}/proxyplugin2-firefox-UNSIGNED.xpi" "${FW_SRC}/proxyplugin2-firefox.xpi"

# неподписанный xpi ставится, но с явным предупреждением
out=$("${FW_ROOT}/install.sh" 2>&1)
case "$out" in
    *"НЕ ПОДПИСАН"*) ;;
    *) fail "установка не предупредила об отсутствии подписи" ;;
esac

# --- Удаление ---------------------------------------------------------------

"${FW_ROOT}/uninstall.sh" --yes > "${SANDBOX}/uninstall.log" 2>&1 \
    || { cat "${SANDBOX}/uninstall.log"; fail "uninstall.sh завершился с ошибкой"; }

[ -e "${FW_SYSROOT}/opt/firewyrm" ] && fail "остался ${FW_SYSROOT}/opt/firewyrm"
[ -e "$manifest" ] && fail "остался манифест"
[ -e "$policy" ] && fail "осталась политика"
python3 - "$FFPOL" "$XPI_ID" <<'PYPOL2' || fail "удаление испортило чужую политику Firefox"
import json, sys
d = json.load(open(sys.argv[1]))
p = d['policies']
assert p.get('DisableTelemetry') is True, 'чужой ключ политики потерян при удалении'
e = p.get('ExtensionSettings', {})
assert 'mis-watch@nokod.local' in e, 'чужое расширение выброшено при удалении'
assert sys.argv[2] not in e, 'наша политика не удалена'
PYPOL2
[ -e "${PROFILE}/extensions/${XPI_ID}.xpi" ] && fail "остался xpi в профиле"
[ -e "${PROFILE2}/extensions/${XPI_ID}.xpi" ] && fail "остался xpi во втором профиле"
[ -e "${ODD}/extensions/${XPI_ID}.xpi" ] \
    && fail "остался xpi в профиле с нестандартным именем"
[ -e "${FW_SYSROOT}/usr/lib64/firefox/distribution/extensions/${XPI_ID}.xpi" ] \
    && fail "остался xpi в distribution/extensions"
[ -e "${FW_SYSROOT}/usr/lib64/mozilla/plugins/npProxyPlugin2.so" ] && fail "остался плагин"

"${FW_ROOT}/install.sh" --check > /dev/null 2>&1 && fail "--check не заметил удаления"

# --check обязан сообщать об остатках, даже когда установки уже нет
mkdir -p "${ODD}/extensions"
touch "${ODD}/extensions/${XPI_ID}.xpi"
check_out=$("${FW_ROOT}/install.sh" --check 2>&1 || true)
case "$check_out" in
    *"остался файл расширения"*) ;;
    *) fail "--check не сообщил об остатке xpi в профиле" ;;
esac
rm -rf "${ODD}"

echo "OK: установка, проверка и удаление отработали"
