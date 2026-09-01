# Расширение ProxyPlugin2 под Firefox

Вендор публикует ProxyPlugin2 только для Chromium. Этот документ описывает,
почему под Firefox потребовалась отдельная сборка, что именно в ней изменено
относительно кода вендора и как её собрать и подписать.

Id расширения в Chrome Web Store — `dpkefahlefbmfgfgfoppbpkacgdmadpp`.
Сборка под Firefox лежит в `firefox-extension/` и является портом оригинала,
а не переписанным кодом:

```
firefox-extension/
├── manifest.json                 переписан: MV2, gecko id, nativeMessaging
├── background.js                 одна правка: чтение port.error
├── content.js                    три правки под Firefox
├── FirePromise.js, icon-128.png  байт-в-байт как у вендора
├── vendor-patch.diff             наши правки в виде патча
└── build.sh                      сборка архива для подписи
```

В репозитории лежат и файлы вендора — они получены из открытых источников:
код расширения из установленного Chromium (расширение публикуется в Chrome Web
Store), бинарники из дистрибутива СЭДД. Правки при этом хранятся ещё и
отдельным патчем `vendor-patch.diff`, чтобы их можно было применить к любой
новой версии вендора и чтобы было видно, что именно изменено.

### Сборка расширения из исходников вендора

Оригинал берётся из установленного в Chromium расширения — политика
устанавливает его сама, распакованный код лежит в профиле:

```bash
cp ~/.config/chromium/Default/Extensions/dpkefahlefbmfgfgfoppbpkacgdmadpp/1.4_0/{FirePromise.js,background.js,content.js,icon-128.png} firefox-extension/
```

`background.js`, `FirePromise.js` и иконка используются без изменений,
к `content.js` применяется патч:

```bash
cd firefox-extension && patch -p0 < vendor-patch.diff && cd ..
```

```bash
./firefox-extension/build.sh
```

Бинарники в `sedd/` (`FireWyrmNativeMessageHost`, `npProxyPlugin2.so`,
`ru.intertrust.firewyrmhost.json`) берутся из дистрибутива СЭДД, который
поставляет Интертраст.

Проверить, что от вендорского кода отличается ровно одна строка:

```bash
diff firefox-extension/upstream-chrome-1.4/content.js firefox-extension/content.js
```

Правки под Firefox — четыре, все вынужденные и объяснимые:

**0. `background.js` — чтение `port.error`.**
Chrome сообщает причину обрыва через `runtime.lastError`, Firefox кладёт её на
сам порт. Без этого страница видит только `Disconnected` без объяснения, а за
ним прячутся самые частые причины: id расширения отсутствует в
`allowed_extensions`, неверный путь в манифесте хоста, бинарник не исполняемый.

**1. `content.js` — `chrome.runtime.connect({name})` вместо `connect(extId, {name})`.**
В Chrome передача собственного id из content script означает подключение к своему
же фону; в Firefox тот же вызов уходит по внешнему каналу (`onConnectExternal`),
и `onConnect` в фоне молчит.

**2. `content.js` — `cloneInto` для `detail` события `FireBreathLoadedEvent`.**
`FirePromise.js` работает в контексте страницы и читает `e.detail.message`, а
объект создаётся в content script. Firefox запрещает такой доступ через границу
миров (Xray): `Permission denied to access property "message"`.

**3. `content.js` — `FirePromise.js` внедряется один раз на страницу.**
Каждое внедрение добавляет свой слушатель `FireBreathLoadedEvent`, поэтому второе
рукопожатие порождало лишние wyrmhole, и ответы приходили не тому экземпляру:
`Invalid msg id!`.

**4. `kickstart.js` — новый файл, обход расхождения серверных бутстрапов.**

Приложение отдаёт браузерам разный код. Chromium получает бутстрап, который зовёт
`load_plugin_in_chrome(callback, error)` — путь через FireWyrm. Firefox получает
бутстрап, который зовёт `load_plugin(dest, callback, error)` — путь через NPAPI,
удалённый из браузеров ещё в 2015–2017 годах. Обе функции на странице определены,
приложение просто вызывает не ту.

`kickstart.js` оборачивает `load_plugin` и переводит вызов на
`load_plugin_in_chrome`, отбрасывая лишний первый аргумент (`dest`) — иначе
колбэк успеха приложения попал бы на DOM-элемент, а колбэк ошибки на обработчик
успеха.

Обёртка ставится по событию **`afterscriptexecute`**, а не по таймеру. GWT
впрыскивает скрипт с `load_plugin` динамически и вызывает его в той же
синхронной задаче — таймеры в этот момент управления не получают и всегда
опаздывают (замерено: обёртка по таймеру вставала через 13 секунд, уже после
провала первой проверки). `afterscriptexecute` — событие Gecko, срабатывает
синхронно сразу после выполнения скрипта, то есть между определением функции и
её вызовом. Замер после правки: обёртка на `+13323ms`, вызов приложения на
`+13325ms` — успеваем с запасом в 2 мс.

Если Gecko когда-нибудь уберёт `afterscriptexecute`, останется запасной опрос по
таймеру: расширение продолжит работать, но первая проверка плагина снова будет
показывать «плагина нет» до повторного нажатия.

Это обход. Правильное решение — на стороне sedd.nso.ru: отдавать Firefox тот же
бутстрап, что и Chromium. Запрос в Intertrust формулируется так: *«В Firefox
приложение вызывает load_plugin (NPAPI) вместо load_plugin_in_chrome, хотя обе
функции на странице определены. Просим включить ветку FireWyrm для Firefox»*.
Обход живёт ровно до тех пор, пока вендор не переименует эти функции.

### Сборка и подпись

```bash
./firefox-extension/build.sh
```

Полученный `proxyplugin2-firefox-UNSIGNED.xpi` отправить на addons.mozilla.org
(Submit → «On your own» — подпись без публикации в каталоге), подписанный файл
положить как `sedd/proxyplugin2-firefox.xpi`. Установщик подхватит его сам.

Пока файла нет, установка идёт без Firefox: Chromium ставится полностью,
в выводе будет предупреждение о пропуске.

### Куда ставится

* `<профиль>/extensions/{aa17458a-0172-46a5-a961-f8028a5883d2}.xpi` для всех профилей
  `*.default*`, владелец — владелец профиля;
* `/usr/lib64/firefox/distribution/extensions/` — для вновь создаваемых профилей;
* `/usr/lib64/mozilla/native-messaging-hosts/ru.intertrust.firewyrmhost.json` —
  манифест хоста с ключом `allowed_extensions` (у Chromium на том же месте
  `allowed_origins` с `chrome-extension://…`, форматы не взаимозаменяемы).

Имя xpi обязано совпадать с `browser_specific_settings.gecko.id`, иначе Firefox
молча его игнорирует. Тот же id стоит в `allowed_extensions`. Меняется в одном
месте — `FW_XPI_ID` в `lib/firewyrm.sh` и `fw_xpi_id` в `ansible/firewyrm_vars.yml`,
плюс сам `manifest.json`; после подписи менять уже нельзя.

Через политику Firefox (`/etc/firefox/policies/policies.json`,
`ExtensionSettings` + `installation_mode: force_installed`) расширение можно
было бы доставить и в существующие профили разом. Установщик этого не делает
намеренно: в отличие от Chromium, Firefox читает **один** файл `policies.json`,
своего файла рядом не положить. На этом же парке машин его уже занимает
MIS Watch, причём с `chattr +i`, поэтому запись сюда либо упала бы с отказом,
либо стёрла чужую политику. Профиль + `distribution/extensions` дают ту же
полноту охвата без этого риска.

### Проверка до подписи

Неподписанную сборку можно проверить сразу, подпись для этого не нужна:
`about:debugging#/runtime/this-firefox` → «Загрузить временное дополнение» →
выбрать `proxyplugin2-firefox-UNSIGNED.xpi`. Живёт до перезапуска браузера.

