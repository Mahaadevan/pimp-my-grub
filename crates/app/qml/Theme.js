.pragma library
// Shared accent colour. Every `Tokens {}` instance registers here, so changing the accent updates the whole UI at once.
var accent = "#ff9248"
var _listeners = []
function register(o) { _listeners.push(o); o.apply(accent) }
function unregister(o) { var i = _listeners.indexOf(o); if (i >= 0) _listeners.splice(i, 1) }
function isHex(c) { return /^#[0-9a-fA-F]{6}$/.test(c) }
function set(c) {
    if (!isHex(c)) return
    accent = c.toLowerCase()
    for (var i = 0; i < _listeners.length; i++) { try { _listeners[i].apply(accent) } catch (e) { } }
}
