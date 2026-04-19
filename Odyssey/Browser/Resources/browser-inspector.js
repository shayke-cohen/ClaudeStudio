// browser-inspector.js
// Injected into every page via WKUserScript at document start.
// Pure vanilla JS — no dependencies, no ES modules, no import/export.
// Namespaced under window.__odyssey (except window.agent which is intentionally global).

window.__odyssey = window.__odyssey || {};

// ---------------------------------------------------------------------------
// 1. Selector resolution
// ---------------------------------------------------------------------------

window.__odyssey.resolveSelector = function(selector) {
  // Support CSS selectors and aria selectors (prefix "aria/")
  var el;
  if (selector.indexOf('aria/') === 0) {
    var label = selector.slice(5);
    el = document.querySelector('[aria-label="' + label + '"]')
      || document.querySelector('[role][aria-label="' + label + '"]')
      || Array.from(document.querySelectorAll('*')).find(function(e) {
           return e.textContent.trim() === label;
         });
  } else {
    el = document.querySelector(selector);
  }
  if (!el) return null;
  var rect = el.getBoundingClientRect();
  return {
    found: true,
    x: rect.x + rect.width / 2,
    y: rect.y + rect.height / 2,
    top: rect.top,
    left: rect.left,
    width: rect.width,
    height: rect.height,
    tagName: el.tagName,
    text: el.textContent ? el.textContent.trim().slice(0, 100) : ''
  };
};

// ---------------------------------------------------------------------------
// 2. Element highlight overlay
// ---------------------------------------------------------------------------

window.__odyssey.highlightElement = function(rect, label) {
  window.__odyssey.clearHighlight();
  var overlay = document.createElement('div');
  overlay.id = '__odyssey_highlight';
  overlay.style.cssText = [
    'position:fixed',
    'top:' + rect.top + 'px',
    'left:' + rect.left + 'px',
    'width:' + rect.width + 'px',
    'height:' + rect.height + 'px',
    'border:2px solid #6dbf6d',
    'border-radius:3px',
    'background:rgba(109,191,109,0.08)',
    'pointer-events:none',
    'z-index:2147483647',
    'transition:all 0.15s ease',
    'box-sizing:border-box'
  ].join(';');

  var tooltip = document.createElement('div');
  tooltip.style.cssText = [
    'position:absolute',
    'top:-22px',
    'left:0',
    'background:#6dbf6d',
    'color:#000',
    'font:bold 11px/1 monospace',
    'padding:3px 6px',
    'border-radius:3px',
    'white-space:nowrap',
    'pointer-events:none'
  ].join(';');
  tooltip.textContent = label || 'agent';
  overlay.appendChild(tooltip);
  document.documentElement.appendChild(overlay);
};

window.__odyssey.clearHighlight = function() {
  var el = document.getElementById('__odyssey_highlight');
  if (el) el.remove();
};

// ---------------------------------------------------------------------------
// 3. Console log capture
// ---------------------------------------------------------------------------

(function() {
  var _logs = [];
  window.__odyssey.getLogs = function() { return _logs.slice(); };

  ['log', 'warn', 'error', 'info', 'debug'].forEach(function(level) {
    var original = console[level].bind(console);
    console[level] = function() {
      var args = Array.from(arguments).map(function(a) {
        try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
        catch(e) { return String(a); }
      });
      _logs.push({ level: level, message: args.join(' '), timestamp: Date.now() });
      if (_logs.length > 500) _logs.shift(); // cap at 500 entries
      original.apply(console, arguments);
      // Post to Swift bridge if available
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.consoleLog) {
        try {
          window.webkit.messageHandlers.consoleLog.postMessage(
            JSON.stringify({ level: level, message: args.join(' '), timestamp: Date.now() })
          );
        } catch(e) {}
      }
    };
  });
})();

// ---------------------------------------------------------------------------
// 4. Accessibility tree export
// ---------------------------------------------------------------------------

window.__odyssey.exportAccessibilityTree = function(maxDepth) {
  maxDepth = maxDepth || 6;
  function walk(el, depth) {
    if (depth > maxDepth) return null;
    var role = el.getAttribute('role') || el.tagName.toLowerCase();
    var label = el.getAttribute('aria-label') || el.getAttribute('alt') || el.getAttribute('placeholder') || '';
    var text = (el.childElementCount === 0) ? (el.textContent ? el.textContent.trim().slice(0, 80) : '') : '';
    var node = { role: role, label: label, text: text, tag: el.tagName.toLowerCase() };
    var children = [];
    for (var i = 0; i < el.children.length; i++) {
      var childNode = walk(el.children[i], depth + 1);
      if (childNode) children.push(childNode);
    }
    if (children.length) node.children = children;
    return node;
  }
  return walk(document.body || document.documentElement, 0);
};

// ---------------------------------------------------------------------------
// 5. Agent submit bridge (for canvas mode)
// ---------------------------------------------------------------------------

window.agent = {
  submit: function(data) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.agentSubmit) {
      try {
        window.webkit.messageHandlers.agentSubmit.postMessage(
          typeof data === 'string' ? data : JSON.stringify(data)
        );
      } catch(e) {}
    }
  },
  update: function(html) {
    if (document.body) document.body.innerHTML = html;
  }
};

// ---------------------------------------------------------------------------
// 6. Page ready notification
// ---------------------------------------------------------------------------

(function() {
  function notifyPageReady() {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pageReady) {
      try {
        window.webkit.messageHandlers.pageReady.postMessage(
          JSON.stringify({ url: location.href, title: document.title })
        );
      } catch(e) {}
    }
  }

  // Notify Swift when page is interactive
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', notifyPageReady);
  } else {
    // Already loaded (injected late)
    notifyPageReady();
  }
})();
