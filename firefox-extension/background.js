/*global chrome*/

var firebreath = {}; //global object
var ports = {};
var hostName = "ru.intertrust.firewyrmhost";
var mimeType = "application/x-proxyplugin2"

/* Using Fire Wyrm via webpage */
chrome.runtime.onConnect.addListener(function(scriptPort) {
    console.log("Connected!");
    var name = scriptPort.name;
    var hostPort = chrome.runtime.connectNative(hostName);
    var self = ports[name] = {
        script: scriptPort,
        host: hostPort
    };
    scriptPort.onMessage.addListener(function(msg) {
        // Message from the content script (from the page),
        // post it to the native message host
        hostPort.postMessage(msg);
    });
    hostPort.onMessage.addListener(function(msg) {
        // Message from the native message host,
        // post it to the content script (to the page)
        scriptPort.postMessage(msg);
    });
    scriptPort.onDisconnect.addListener(function() {
        // The script disconnected, so disconnect the hostPort
        hostPort.disconnect();
    });
    hostPort.onDisconnect.addListener(function() {
        // The host (native message host) disconnected, so disconnect
        // the script port. If there is an error, report it first
        // Firefox port: Chrome reports the reason through runtime.lastError,
        // Firefox puts it on the port itself (port.error). Without reading both
        // the page only sees a bare "Disconnected" with no explanation - which
        // hides the common causes: extension id missing from allowed_extensions,
        // wrong path in the host manifest, host binary not executable.
        var reason = (chrome.runtime.lastError && chrome.runtime.lastError.message) ||
                     (hostPort.error && hostPort.error.message) || "";
        if (reason) {
            scriptPort.postMessage({error: "Disconnected", message: reason});
            console.warn("Disconnected:", reason);
        } else {
            scriptPort.postMessage({error: "Disconnected"});
        }
        scriptPort.disconnect();
    });
});
