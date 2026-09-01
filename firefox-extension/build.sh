#!/bin/bash
# Сборка архива для проверки и для отправки на подпись
# (addons.mozilla.org -> Submit -> "On your own").
# Подписанный файл класть как sedd/proxyplugin2-firefox.xpi
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

out="../proxyplugin2-firefox-UNSIGNED.xpi"
rm -f "$out"
zip -r -q -FS "$out" manifest.json background.js content.js kickstart.js FirePromise.js icon-128.png

# Файл, упомянутый в манифесте, но не попавший в архив, ломает расширение молча.
python3 - "$out" <<'PY'
import json, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = set(z.namelist())
m = json.loads(z.read('manifest.json'))
need = set(m['background']['scripts'])
for cs in m['content_scripts']:
    need |= set(cs['js'])
need |= set(m.get('web_accessible_resources', []))
need |= set(m.get('icons', {}).values())
missing = need - names
if missing:
    sys.exit('ОШИБКА: в архиве нет файлов из манифеста: ' + ', '.join(sorted(missing)))
print('В архиве: ' + ', '.join(sorted(names)))
PY

echo "Собрано: $(cd .. && pwd)/proxyplugin2-firefox-UNSIGNED.xpi"
