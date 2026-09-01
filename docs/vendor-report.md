# ProxyPlugin2 CMJ Plugin Adapter в Firefox: причина неработоспособности и исправление

Отчёт для ООО «Интертраст», разработчика Company Media / ProxyPlugin2.

Подготовлено при внедрении СЭДД на рабочих станциях под ALT Linux.
Контекст: расширение `dpkefahlefbmfgfgfoppbpkacgdmadpp` в Chrome Web Store
работает штатно; в Firefox плагин недоступен.

## Суть проблемы

Веб-приложение отдаёт браузерам разные варианты кода загрузки плагина.
На странице определены **обе** функции:

```js
load_plugin(dest, callback, error)        // NPAPI: <object type="application/x-proxyplugin2">
load_plugin_in_chrome(callback, error)    // FireWyrm: postMessage -> FirePromise.js -> connectNative
```

В Chromium приложение вызывает `load_plugin_in_chrome` и плагин поднимается.
В Firefox приложение вызывает `load_plugin`, то есть путь через NPAPI.

NPAPI удалён из Chromium в 2015 году и из Firefox в версии 52 (2017 год).
`<object type="application/x-proxyplugin2">` в современном браузере остаётся
пустым элементом, поэтому вызов заканчивается так:

```
TypeError: proxyPlugin_().setStreamHelper is not a function
error loading plugin
Таймаут загрузки плагина.
```

Приложение повторяет попытку и снова получает тот же результат.

**Ключевой факт: `load_plugin_in_chrome` в Firefox на странице присутствует и
полностью работоспособна.** Приложение просто её не вызывает. Проверено прямым
вызовом: плагин загружается, нативный хост отвечает `status: success`.

## Что потребовалось для работы в Firefox

Четыре изменения относительно кода расширения версии 1.4. Первые три —
объективные различия платформ, они потребовались бы в любой сборке под Firefox.
Четвёртое — обход описанной выше проблемы на стороне сервера.

### 1. `content.js`: подключение к фоновой странице

```js
- var port = chrome.runtime.connect(extId, {name: portName});
+ var port = chrome.runtime.connect({name: portName});
```

В Chrome передача собственного id из content script означает подключение к своей
же фоновой странице. В Firefox тот же вызов трактуется как внешнее подключение
(`onConnectExternal`), и обработчик `onConnect` в фоне не срабатывает.

### 2. `content.js`: передача данных события в контекст страницы

```js
- window.dispatchEvent(new CustomEvent('FireBreathLoadedEvent', {
-     'detail': { 'message': id + "|" + function_name }
- }));
+ var detail = {message: id + "|" + function_name};
+ if (typeof cloneInto === 'function') { detail = cloneInto(detail, window); }
+ window.dispatchEvent(new CustomEvent('FireBreathLoadedEvent', {detail: detail}));
```

`FirePromise.js` исполняется в контексте страницы и читает `e.detail.message`.
Объект создаётся в content script, а Firefox изолирует эти два мира (Xray
vision). Без `cloneInto` возникает:

```
Uncaught Error: Permission denied to access property "message"
    at FirePromise.js:2
```

### 3. `content.js`: однократное внедрение `FirePromise.js`

Каждое внедрение добавляет собственный обработчик `FireBreathLoadedEvent`.
При повторном рукопожатии создаются лишние wyrmhole, и ответы приходят
экземпляру, который соответствующую команду не отправлял:

```
Uncaught Error: Invalid msg id!
    at processCompleteMessage (FirePromise.js:1302)
```

### 4. Обход выбора не той функции загрузки

Отдельный скрипт в контексте страницы оборачивает `load_plugin` и переводит
вызов на `load_plugin_in_chrome`, отбрасывая лишний первый аргумент `dest`
(сигнатуры отличаются на один параметр — без этого колбэк успеха приложения
попадает на DOM-элемент, а колбэк ошибки на обработчик успеха).

Существенная деталь реализации: обёртка ставится по событию
`afterscriptexecute`, а не по таймеру. Скрипт с `load_plugin` впрыскивается GWT
динамически и вызывается в той же синхронной задаче, поэтому таймеры в этот
момент управления не получают. Замер: обёртка по таймеру вставала на +12992 мс,
уже после провала первой проверки; по `afterscriptexecute` — на +13323 мс,
вызов приложения на +13325 мс, то есть с запасом в 2 мс.

## Что просим

Пункт 4 — обход, который живёт ровно до ближайшего переименования функций на
вашей стороне и который мы вынуждены поддерживать сами. Просим включить для
Firefox тот же путь загрузки плагина, что используется для Chromium: вызывать
`load_plugin_in_chrome` вместо `load_plugin`. На стороне приложения это условие
выбора ветки, обе функции уже есть на странице.

Пункты 1–3 — готовые исправления для сборки расширения под Firefox. Готовы
передать полный диф и сборку. Если вы выпустите официальную версию для Firefox,
мы перейдём на неё и снимем свою.

## Проверено на

ALT Linux c10f2, Firefox, СЭДД sedd.nso.ru (Company Media 4),
`FireWyrmNativeMessageHost` и `npProxyPlugin2.so` из вашего дистрибутива,
без изменений. Нативный хост, манифест native messaging и загрузка
`npProxyPlugin2.so` работают штатно, вмешательства не потребовали.
