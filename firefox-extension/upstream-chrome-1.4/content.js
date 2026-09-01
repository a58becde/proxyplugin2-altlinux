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
        var port = chrome.runtime.connect(extId, {name: portName});
        ports[portName] = port;

        window.postMessage({
            source: "host",
            port: portName,
            ext: extId,
            message: "Created"
        }, "*");
        port.onMessage.addListener(function(msg) {
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

    function initPage(evt) {
        injectScript(extId, evt.callback);
    }

    function injectScript(id, function_name) { //injecting javascript by text
        var s = document.createElement('script');
        s.src = chrome.runtime.getURL('FirePromise.js');
        s.onload = function() {
            this.remove();
            window.dispatchEvent(new CustomEvent('FireBreathLoadedEvent', {
                'detail': {
                    'message': id + "|" + function_name
                }
            }));
        };
        (document.head || document.documentElement).appendChild(s);
    }
})();

