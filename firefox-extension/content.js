/*global chrome, Promise*/
(function() {

    var nextId = 1;
    var ports = {};
    var extId = chrome.runtime.id;
    var firebreathId = 'InterTrust';

    window.addEventListener("message", function(event) {
        // We only accept messages from ourselves
        if (event.source != window) { return; }

        if (event.data && event.data.source && event.data.source == "page" && event.data.ext == extId) {
            handleEvent(event.data);
        }

        if (event.data && event.data.firebreath == firebreathId && event.data.callback) {
            initPage(event.data);
        }
    }, false);

    function handleEvent(evt) {
        if (evt.request == "Create") {
            createWyrmhole();
        } else if (evt.port) {
            var port = evt.port;
            delete evt.port;
            delete evt.source;
            if (ports[port]) {
                // Message from the page received, post it to the background script
                ports[port].postMessage(evt);
            } else {
                // Invalid port!
                window.postMessage({
                    source: "host",
                    port: port,
                    ext: extId,
                    message: "Error",
                    error: "Invalid port"
                }, "*");
            }
        }
    }

    function createWyrmhole() {
        var portName = "FireWyrmPort" + (nextId++);
        // Firefox port: do not pass our own extension id here. In Chrome,
        // connect(extId, ...) from a content script reaches our own
        // background page; in Firefox the same call goes out over the
        // external channel (onConnectExternal) and onConnect stays silent.
        var port = chrome.runtime.connect({name: portName});
        console.log('[FireWyrm-FF] wyrmhole port created: ' + portName);
        ports[portName] = port;

        window.postMessage({
            source: "host",
            port: portName,
            ext: extId,
            message: "Created"
        }, "*");
        port.onMessage.addListener(function(msg) {
            if (msg && msg.status) {
                console.log('[FireWyrm-FF] host status: ' + msg.status +
                            (msg.plugin !== undefined ? ', plugin=' + msg.plugin : ''));
            }
            if (msg && msg.error) {
                console.warn('[FireWyrm-FF] native host error: ' + msg.error +
                             (msg.message ? ' / ' + msg.message : ''));
            }
            // Message from the background script received, post it to the page
            msg.source = "host";
            msg.port = portName;
            msg.ext = extId;
            window.postMessage(msg, "*");
        });
        port.onDisconnect.addListener(function() {
            // The host port disconnected; tell the window
            window.postMessage({
                source: "host",
                port: portName,
                ext: extId,
                message: "Disconnected"
            }, "*");
            delete ports[portName];
        });
    }

    // Firefox: the page does not start the handshake itself (Chromium gets a
    // different bootstrap). Start the vendor's own protocol from our side.
    (function () {
        var s = document.createElement('script');
        s.src = chrome.runtime.getURL('kickstart.js');
        s.onload = function () { this.remove(); };
        (document.head || document.documentElement).appendChild(s);
    })();

    var firePromiseInjected = false;

    function initPage(evt) {
        console.log('[FireWyrm-FF] handshake from page, callback=' + evt.callback);
        // Each injection adds another FireBreathLoadedEvent listener, so a
        // second handshake would create extra wyrmholes and answers would
        // reach the wrong instance ("Invalid msg id!"). Inject once.
        if (firePromiseInjected) {
            console.log('[FireWyrm-FF] FirePromise.js already injected, duplicate ignored');
            return;
        }
        firePromiseInjected = true;
        injectScript(extId, evt.callback);
    }

    function injectScript(id, function_name) { //injecting javascript by text
        var s = document.createElement('script');
        s.src = chrome.runtime.getURL('FirePromise.js');
        s.onload = function() {
            this.remove();
            // Firefox port: objects created in the content script cannot be read
            // from page context (Xray vision). FirePromise.js reads
            // e.detail.message, so the detail must be cloned into the page's
            // compartment first, otherwise it throws
            // "Permission denied to access property message".
            var detail = {message: id + "|" + function_name};
            if (typeof cloneInto === 'function') {
                detail = cloneInto(detail, window);
            }
            window.dispatchEvent(new CustomEvent('FireBreathLoadedEvent', {detail: detail}));
        };
        (document.head || document.documentElement).appendChild(s);
    }
})();

