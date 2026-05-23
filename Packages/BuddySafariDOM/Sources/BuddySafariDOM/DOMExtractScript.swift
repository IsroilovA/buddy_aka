import Foundation

// The JS payloads we feed to Safari via `do JavaScript`. Kept as Swift string
// constants (not bundled .js resources) so the package has zero runtime
// resource lookups - AppleScript's `do JavaScript` accepts any string.
//
// Selector and label-resolution rules in `extractScript` mirror what an
// accessibility-aware screen reader does: prefer aria-label -> aria-labelledby
// -> <label for> -> wrapping <label> -> title -> placeholder/alt -> innerText. The
// projection is INTENTIONALLY narrow - only interactive and contextual nodes
// (headings, labels, captions) survive, so a typical viewport produces a few
// KB of JSON instead of a few hundred KB of raw HTML.
//
// CSS paths use only `tag:nth-of-type(n)` segments - no ids, no quotes - so
// they round-trip through AppleScript without escaping headaches.
enum DOMExtractScript {

    static let extract: String = #"""
    (function() {
      const TAGS_SKIP = new Set(['script','style','noscript','meta','link','svg','path','defs','use','title','head']);
      const INTERACTIVE_TAGS = new Set(['button','input','select','textarea']);
      const INTERACTIVE_ROLES = new Set(['button','link','checkbox','radio','tab','menuitem','menuitemcheckbox','menuitemradio','option','switch','combobox','searchbox','slider','spinbutton','treeitem','textbox']);
      const HEADING_TAGS = new Set(['h1','h2','h3','h4','h5','h6']);
      const LABEL_TAGS = new Set(['label','legend','caption','figcaption','summary']);
      const ROLE_NORMALIZE = {
        a: 'link', button: 'button', input: 'textfield', select: 'combobox', textarea: 'textfield',
        h1: 'heading', h2: 'heading', h3: 'heading', h4: 'heading', h5: 'heading', h6: 'heading',
        label: 'label', legend: 'label', caption: 'label', figcaption: 'label', summary: 'label',
        img: 'image'
      };

      const startedAt = Date.now();
      const items = [];
      let scanned = 0;
      let nextId = 0;

      function clampText(s, n) {
        s = (s || '').toString().trim().replace(/\s+/g, ' ');
        return s.length > n ? s.slice(0, n - 3) + '...' : s;
      }

      function isHidden(el, cs) {
        if (el.hidden) return true;
        if (el.getAttribute('aria-hidden') === 'true') return true;
        if (cs.display === 'none' || cs.visibility === 'hidden' || cs.visibility === 'collapse') return true;
        if (parseFloat(cs.opacity) === 0) return true;
        return false;
      }

      function isInteractive(el, tag) {
        if (tag === 'a') return el.hasAttribute('href');
        if (INTERACTIVE_TAGS.has(tag)) return true;
        const role = el.getAttribute('role');
        if (role && INTERACTIVE_ROLES.has(role)) return true;
        if (el.hasAttribute('onclick')) return true;
        const ti = el.getAttribute('tabindex');
        if (ti != null && ti !== '' && ti !== '-1') return true;
        if (el.isContentEditable) return true;
        return false;
      }

      function isContextual(tag) {
        return HEADING_TAGS.has(tag) || LABEL_TAGS.has(tag);
      }

      function role(el, tag) {
        const aria = el.getAttribute('role');
        if (aria) return aria;
        return ROLE_NORMALIZE[tag] || tag;
      }

      function accessibleName(el, tag) {
        const al = el.getAttribute('aria-label');
        if (al && al.trim()) return clampText(al, 200);

        const lblBy = el.getAttribute('aria-labelledby');
        if (lblBy) {
          const t = lblBy.split(/\s+/)
            .map(id => (document.getElementById(id) || {}).innerText || '')
            .join(' ');
          if (t.trim()) return clampText(t, 200);
        }

        if (el.id) {
          try {
            const lbl = document.querySelector('label[for="' + CSS.escape(el.id) + '"]');
            if (lbl && lbl.innerText && lbl.innerText.trim()) return clampText(lbl.innerText, 200);
          } catch (_) { /* invalid id */ }
        }

        if (typeof el.closest === 'function') {
          const lbl = el.closest('label');
          if (lbl && lbl !== el && lbl.innerText && lbl.innerText.trim()) {
            return clampText(lbl.innerText, 200);
          }
        }

        const title = el.getAttribute('title');
        if (title && title.trim()) return clampText(title, 200);

        if (tag === 'input' || tag === 'textarea') {
          if (el.placeholder) return clampText(el.placeholder, 200);
          if (el.value && (el.type === 'button' || el.type === 'submit' || el.type === 'reset')) {
            return clampText(el.value, 200);
          }
        }

        if (tag === 'img') {
          const alt = el.getAttribute('alt');
          if (alt) return clampText(alt, 200);
        }

        return clampText(el.innerText, 200);
      }

      function accessibleDescription(el) {
        const ad = el.getAttribute('aria-description');
        if (ad && ad.trim()) return clampText(ad, 200);

        const descBy = el.getAttribute('aria-describedby');
        if (descBy) {
          const t = descBy.split(/\s+/)
            .map(id => (document.getElementById(id) || {}).innerText || '')
            .join(' ');
          if (t.trim()) return clampText(t, 200);
        }

        const title = el.getAttribute('title');
        if (title && title.trim()) return clampText(title, 200);
        return '';
      }

      function valueOf(el, tag) {
        if (tag === 'input' || tag === 'textarea' || tag === 'select') {
          const v = (el.value || '').toString();
          return v ? clampText(v, 120) : '';
        }
        return '';
      }

      function inputType(el, tag) {
        if (tag === 'input') return (el.getAttribute('type') || 'text').toLowerCase();
        return '';
      }

      function cssPath(el) {
        const parts = [];
        let cur = el;
        while (cur && cur.nodeType === 1 && cur !== document.documentElement) {
          let part = cur.tagName.toLowerCase();
          const parent = cur.parentElement;
          if (parent) {
            const same = Array.from(parent.children).filter(c => c.tagName === cur.tagName);
            if (same.length > 1) {
              const idx = same.indexOf(cur) + 1;
              part += ':nth-of-type(' + idx + ')';
            }
          }
          parts.unshift(part);
          cur = parent;
        }
        return 'html>' + parts.join('>');
      }

      function walk(el) {
        // Hard safety cap; in practice extraction completes in well under 500ms.
        if (Date.now() - startedAt > 4000) return true;
        scanned++;
        const tag = el.tagName.toLowerCase();
        if (TAGS_SKIP.has(tag)) return false;

        let cs;
        try { cs = getComputedStyle(el); } catch (_) { cs = null; }
        if (cs && isHidden(el, cs)) return false;

        const interactive = isInteractive(el, tag);
        const contextual = isContextual(tag);
        if (interactive || contextual) {
          const r = el.getBoundingClientRect();
          const inView = !(r.bottom < 0 || r.top > innerHeight || r.right < 0 || r.left > innerWidth);
          if (r.width > 0 && r.height > 0 && inView) {
            const node = {
              id: 'd_' + (++nextId),
              tag: tag,
              role: el.getAttribute('role') || '',
              type: inputType(el, tag),
              label: accessibleName(el, tag),
              description: accessibleDescription(el),
              interactive: interactive,
              focused: (el === document.activeElement),
              enabled: !el.disabled && el.getAttribute('aria-disabled') !== 'true',
              frame: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
              path: cssPath(el),
              name: el.getAttribute('name') || '',
              dom_id: el.getAttribute('id') || ''
            };
            const value = valueOf(el, tag);
            if (value) node.value = value;
            const placeholder = el.getAttribute && el.getAttribute('placeholder');
            if (placeholder) node.placeholder = clampText(placeholder, 120);
            const href = el.getAttribute && el.getAttribute('href');
            if (href) node.href = clampText(href, 120);
            items.push(node);
          }
        }

        for (let child = el.firstElementChild; child; child = child.nextElementSibling) {
          if (walk(child)) return true;
        }
        return false;
      }

      const truncated = walk(document.documentElement);
      const vv = window.visualViewport;

      return JSON.stringify({
        url: location.href,
        title: document.title,
        viewport: {
          w: vv ? vv.width : innerWidth,
          h: vv ? vv.height : innerHeight,
          scrollX: scrollX,
          scrollY: scrollY,
          dpr: devicePixelRatio,
          visualOffsetX: vv ? vv.offsetLeft : 0,
          visualOffsetY: vv ? vv.offsetTop : 0,
          visualScale: vv ? vv.scale : 1
        },
        stats: { scanned: scanned, kept: items.length, elapsedMs: Date.now() - startedAt, truncated: !!truncated },
        items: items
      });
    })();
    """#

    /// Builds a one-shot resolver script that re-queries the live element at
    /// `path` and returns its current viewport-relative rect. Returns `null`
    /// when the element is gone. This is read-only; it does not scroll, focus,
    /// or mutate the page.
    ///
    /// The path is generated by `extract`'s `cssPath()` and contains only
    /// `tag:nth-of-type(n)` segments (no quotes, no ids), so direct string
    /// interpolation is safe.
    static func resolveScript(path: String) -> String {
        return """
        (function(){
          var el;
          try { el = document.querySelector(\"\(path)\"); } catch (e) { return JSON.stringify(null); }
          if (!el) return JSON.stringify(null);
          var r = el.getBoundingClientRect();
          return JSON.stringify({
            x: Math.round(r.x), y: Math.round(r.y),
            w: Math.round(r.width), h: Math.round(r.height),
            viewport: { w: innerWidth, h: innerHeight, scrollX: scrollX, scrollY: scrollY }
          });
        })();
        """
    }
}
