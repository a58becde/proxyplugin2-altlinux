/* Firefox kickstart for the FireWyrm bridge.
 *
 * The page defines two plugin loaders:
 *   load_plugin(dest, callback, error)   - legacy NPAPI via
 *                                          <object type="application/x-proxyplugin2">,
 *                                          dead since NPAPI was removed from browsers
 *   load_plugin_in_chrome(callback, error) - the FireWyrm path: posts the handshake and
 *                                            gets the plugin through the native host
 *
 * Chromium is served a bootstrap that calls the second one straight away. Firefox
 * calls the first, and load_plugin_in_chrome only shows up on the page later - after
 * the application has already given up and reported "no plugin".
 *
 * So a plain reassignment is not enough: at the moment of the first call there is
 * nothing to redirect to. Instead we wrap load_plugin and remember the callbacks the
 * application passed. As soon as load_plugin_in_chrome appears we invoke it with those
 * same callbacks, so the application learns the plugin is ready by itself, without the
 * user re-running the check.
 *
 * The vendor's legacy call is still made when the FireWyrm path is not available yet:
 * whatever the application does on failure keeps happening, we only add a second,
 * working attempt on top.
 */
(function () {
    'use strict';

    var INTERVAL = 50;
    var DEADLINE = 120000;
    var waited = 0;

    var legacy = null;    // оригинальный load_plugin вендора
    var pending = null;   // аргументы вызова, ждущие появления chrome-пути
    var served = false;

    function stamp() {
        return '+' + Math.round(performance.now()) + 'ms ';
    }

    function chromeReady() {
        return typeof window.load_plugin_in_chrome === 'function';
    }

    function callChrome(args) {
        var a = args.slice();
        // load_plugin(dest, callback, error) -> load_plugin_in_chrome(callback, error)
        if (a.length && typeof a[0] !== 'function') {
            a.shift();
        }
        console.log('[FireWyrm-FF] ' + stamp() + 'calling load_plugin_in_chrome, args: ' +
                    a.map(function (x) { return typeof x; }).join(', '));
        served = true;
        try {
            return window.load_plugin_in_chrome.apply(window, a);
        } catch (e) {
            console.warn('[FireWyrm-FF] load_plugin_in_chrome threw: ' + e);
        }
    }

    function install() {
        if (typeof window.load_plugin !== 'function' || window.load_plugin.__fireWyrm) {
            return;
        }
        legacy = window.load_plugin;

        var wrapper = function () {
            var args = Array.prototype.slice.call(arguments);
            if (chromeReady()) {
                return callChrome(args);
            }
            console.log('[FireWyrm-FF] ' + stamp() +
                        'load_plugin called, load_plugin_in_chrome not defined yet - ' +
                        'running vendor legacy path and waiting for it');
            pending = args;
            try {
                return legacy.apply(window, args);
            } catch (e) {
                console.warn('[FireWyrm-FF] legacy load_plugin threw: ' + e);
            }
        };
        wrapper.__fireWyrm = true;
        window.load_plugin = wrapper;
        console.log('[FireWyrm-FF] ' + stamp() + 'load_plugin wrapped');
    }

    // GWT впрыскивает скрипт с load_plugin и вызывает его в той же синхронной
    // задаче, поэтому опрос по таймеру всегда опаздывает: управление к нему
    // возвращается уже после первого вызова. afterscriptexecute (Gecko) срабатывает
    // сразу после выполнения каждого скрипта, синхронно - это единственная точка,
    // где можно успеть обернуть функцию до того, как приложение её позовёт.
    document.addEventListener('afterscriptexecute', function () {
        install();
    }, true);

    function tick() {
        install();

        if (pending && chromeReady()) {
            var args = pending;
            pending = null;
            console.log('[FireWyrm-FF] ' + stamp() +
                        'load_plugin_in_chrome appeared - retrying the pending call');
            callChrome(args);
        }

        waited += INTERVAL;
        if (waited >= DEADLINE) {
            if (!served && typeof window.load_plugin === 'function') {
                console.warn('[FireWyrm-FF] load_plugin_in_chrome never appeared on this page');
            }
            return;
        }
        setTimeout(tick, INTERVAL);
    }

    tick();
})();
