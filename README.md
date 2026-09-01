# FireWyrm (СЭДД) — установщик для ALT Linux

Развёртывание плагина ЭП системы электронного документооборота Company Media
(«Интертраст») на рабочих станциях под ALT Linux: нативный хост
`FireWyrmNativeMessageHost`, библиотека `npProxyPlugin2.so`, манифесты
native messaging, политики принудительной установки расширения — для Chromium
и для Firefox.

Два способа установки, оба делают одно и то же: обычные shell-скрипты и
плейбуки Ansible. `sudo` не используется нигде — в ALT Linux его нет,
всё выполняется от root после `su -`.

> **Неофициальный установщик.** Не связан с ООО «Интертраст» и не
> поддерживается им. Разработан для внутреннего развёртывания СЭДД
> на рабочих станциях под ALT Linux.

## Что решает

Штатный установщик вендора раскладывает файлы в домашний каталог одного
пользователя и рассчитан на NPAPI, вырезанный из браузеров в 2015–2017 годах.
Здесь вместо этого:

* **общесистемная установка** — работает для всех пользователей машины, имя
  пользователя и путь к его домашнему каталогу нигде не нужны;
* **расширение ставится политикой** — Chromium подтягивает его из Chrome Web
  Store сам, Firefox получает подписанную сборку через `ExtensionSettings`;
* **работающий мост в Firefox** — вендорская поддержка Firefox сделана через
  NPAPI и в современном браузере мертва, см. [docs/firefox-port.md](docs/firefox-port.md);
* **проверяемость** — `install.sh --check` показывает состояние установки
  целиком, `test.sh` прогоняет установку и удаление в песочнице.

## Требования

* **ALT Linux**, доступ root (`su -`). Проверено на ALT SP Workstation 10
  (10.2.2, ветка c10f2, ядро 6.12.103, x86_64)
* **Chromium** — ставится автоматически, если не найден. Проверено на
  139.0.7258.138 (сборка ALT Linux)
* **Firefox ESR** — опционально, только если нужна работа СЭДД в нём.
  Проверено на 140.13.0 ESR
* `python3` — для проверки xpi и слияния политик Firefox
* Для варианта с Ansible: ansible-core на управляющем узле,
  проверено на 2.15.9 с Python 3.9
* Дистрибутив вендора в `sedd/`: `FireWyrmNativeMessageHost`,
  `npProxyPlugin2.so`, `ru.intertrust.firewyrmhost.json`
* Для Firefox: подписанный `sedd/proxyplugin2-firefox.xpi`
  (см. [docs/firefox-port.md](docs/firefox-port.md)); без него ставится
  только Chromium

Полная проверенная конфигурация, включая версию СЭДД — в разделе
[Проверено на](#проверено-на).

## Установка

### Вариант 1 — без Ansible

```bash
su -
/путь/к/install.sh
```

```bash
/путь/к/install.sh --check
```

```bash
/путь/к/uninstall.sh
```

`uninstall.sh --yes` — без запроса подтверждения.

### Вариант 2 — Ansible

Файлы плейбука самодостаточны: `firewyrm_install.yml`,
`firewyrm_uninstall.yml` и `firewyrm_vars.yml` должны лежать рядом друг с
другом. Каталог `sedd/` нужен на управляющем узле — файлы раздаются с него, на
целевые машины заранее копировать ничего не надо.

```bash
scp ansible/firewyrm_*.yml root@<управляющий-узел>:/etc/ansible/playbook/
```

```bash
rsync -av --exclude .DS_Store sedd/ root@<управляющий-узел>:/etc/ansible/sedd/
```

```bash
ansible-playbook -i /etc/ansible/hosts firewyrm_install.yml -e fw_hosts=ws-01
```

`fw_hosts` — это шаблон целей ansible, а не переменная из инвентаря. Принимает
имя хоста, список через запятую без пробелов, маску или имя группы:

```bash
ansible-playbook -i /etc/ansible/hosts firewyrm_install.yml -e fw_hosts=ws-01,ws-02,ws-03
```

Без `-e fw_hosts=...` цель — группа `firewyrm`. Если её нет в инвентаре,
плейбук ничего не сделает («skipping: no hosts matched») вместо того, чтобы
уехать на все машины. Для регулярных выкаток удобнее завести группу в
инвентаре и обращаться к ней по имени.

Повышение прав идёт через `su` (`become_method: su` задан в самих плейбуках).
Если вход на целевую машину не под root, добавьте `-K`.

## Что и куда ставится

| Что | Куда |
| --- | --- |
| `FireWyrmNativeMessageHost` | `/opt/firewyrm/bin/` (0755, root) |
| `npProxyPlugin2.so` | `/usr/lib64/mozilla/plugins/` (0644, root) |
| Манифест native messaging (Chromium) | `/etc/chromium/native-messaging-hosts/` и аналоги остальных браузеров |
| Манифест native messaging (Firefox) | `/usr/lib64/mozilla/native-messaging-hosts/` — формат отличается: `allowed_extensions` вместо `allowed_origins` |
| Политика Chromium | `/etc/chromium/policies/managed/firewyrm.json` и аналоги |
| Политика Firefox | `/etc/firefox/policies/policies.json` — **слиянием**, чужие ключи сохраняются |
| Расширение Firefox | профили из `profiles.ini` и `distribution/extensions` |

Установка общесистемная, поэтому имя пользователя нигде не требуется. Каталог
`/usr/lib64/mozilla/plugins` выбран не произвольно: сам
`FireWyrmNativeMessageHost` сканирует только `$HOME/.mozilla/plugins`,
`/usr/lib/mozilla/plugins` и `/usr/lib64/mozilla/plugins` — эти пути зашиты в
бинарнике, — и подгружает оттуда библиотеки с символом `FireWyrm_Init`.

Политики пишутся сразу в каталоги `/etc/chromium` и `/etc/chromium-browser`:
разные сборки Chromium используют разные префиксы, лишний файл безвреден.

Старые пользовательские копии манифеста в `~/.config/*/NativeMessagingHosts/`
удаляются при установке — пользовательский манифест перекрывает общесистемный,
и без очистки браузер продолжил бы ходить по старому пути.

## Политика установки расширения Chromium

```json
{
  "ExtensionInstallForcelist": [
    "dpkefahlefbmfgfgfoppbpkacgdmadpp;https://clients2.google.com/service/update2/crx"
  ],
  "ExtensionInstallSources": ["https://sedd.nso.ru/*"]
}
```

Пишется в отдельный файл `firewyrm.json`, а не в общий — Chromium читает все
файлы каталога `managed/`, поэтому чужие политики не затрагиваются.

## Проверка

```bash
./test.sh
```

Смоук-тест: разворачивает установку во временный каталог, проверяет содержимое
манифестов и политик, слияние `policies.json` с чужими ключами, обнаружение
неподписанного xpi и xpi с чужим id, установку в профили из `profiles.ini`,
затем удаление и отсутствие следов. Root не нужен, систему не трогает.

```bash
./install.sh --check
```

Состояние реальной установки: бинарник, библиотека, манифесты всех браузеров,
политики, расширение во всех профилях. После удаления обязан **не** проходить —
это и есть доказательство очистки.

Порядок приёмки на машине описан в [docs/acceptance.md](docs/acceptance.md).

## Настройка

Все пути и идентификаторы — переменные в [lib/firewyrm.sh](lib/firewyrm.sh)
и [ansible/firewyrm_vars.yml](ansible/firewyrm_vars.yml), переопределяются
через окружение:

```bash
FW_SRC=/mnt/flash/sedd FW_PREFIX=/opt/sedd ./install.sh
```

Полезные: `FW_SRC`, `FW_PREFIX`, `FW_XPI_ID`, `FW_EXT_ID`, `FW_EXT_UPDATE_URL`,
`FW_EXT_SOURCE`, `FW_PACKAGE`, `FW_SYSROOT` (установка в chroot или образ).

`FW_XPI_ID` связывает три вещи: имя файла в профиле Firefox,
`allowed_extensions` в манифесте хоста и id внутри самого xpi. Менять его нужно
согласованно во всех местах — установщик проверяет совпадение и отказывается
работать при расхождении.

## Структура

```
install.sh, uninstall.sh   установка и удаление без Ansible
test.sh                    смоук-тест в песочнице, root не нужен
lib/firewyrm.sh            общие пути, параметры и функции
ansible/                   те же сценарии на Ansible
firefox-extension/         сборка расширения под Firefox
sedd/                      дистрибутив вендора
docs/                      порт под Firefox, приёмка, отчёт для вендора
```

## Проверено на

| | |
| --- | --- |
| ОС | ALT SP Workstation 10 (10.2.2, ветка c10f2) |
| Ядро | 6.12.103-6.12-alt0.c10f.2, x86_64 |
| Chromium | 139.0.7258.138 (сборка ALT Linux) |
| Firefox | 140.13.0 ESR |
| СЭДД | Company Media 6, версия 6.3.1 |
| Расширение Chromium | ProxyPlugin2 CMJ Plugin Adapter 1.4 (Chrome Web Store) |
| Сборка для Firefox | 1.4.2 |
| Ansible | core 2.15.9, Python 3.9 |

Проверены оба варианта установки и удаления — shell-скриптами и Ansible.
Остальные браузеры из списка (Google Chrome, Chromium-GOST, Яндекс.Браузер)
не проверялись: пути для них взяты из установщика вендора и считаются верными.

Firefox 140 ESR понимает `browser_specific_settings.gecko.data_collection_permissions`
(ключ появился в 140), поэтому предупреждение валидатора AMO о
`strict_min_version` на этой конфигурации ни на что не влияет.

## Правовой статус

Код установщика (`install.sh`, `uninstall.sh`, `lib/`, `ansible/`, `test.sh`,
`firefox-extension/manifest.json`, `firefox-extension/kickstart.js`) написан
для внутреннего развёртывания и распространяется как есть.

Файлы в `sedd/`, а также `background.js`, `content.js`, `FirePromise.js` и
`icon-128.png` в `firefox-extension/` принадлежат ООО «Интертраст» и включены
здесь для воспроизводимости сборки. Правки, внесённые в код вендора, вынесены
отдельно в `firefox-extension/vendor-patch.diff` — он применяется к оригиналу
и даёт итоговые файлы байт-в-байт.

Сборка под Firefox — обход дефекта совместимости, а не форк. Описание проблемы
и предложение вендору: [docs/vendor-report.md](docs/vendor-report.md).
