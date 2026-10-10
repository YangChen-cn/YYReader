/// Capture only image addresses already made public by the website's normal reader.
/// WebKit remains a source of data, never the comic rendering surface.
enum MangaSnapshotScripts {
    // Await public asynchronous rendering only for a chapter-like page with
    // unresolved image slots. Ordinary HTML pages do not incur this wait.
    static let hasPendingReader = #"""
    (() => {
      const chapter = [...document.querySelectorAll('a')].some(a => /^(?:上一话|下一话|上一章|下一章|Previous Chapter|Next Chapter)$/i.test(a.textContent.trim()))
        || /第\s*[0-9一二三四五六七八九十百千]+\s*[话話章]|(?:chapter|episode)\s*\d+/i.test(document.querySelector('h1')?.textContent || '');
      return chapter && [...document.querySelectorAll('img')].some(image =>
        !image.getAttribute('src') && !image.currentSrc);
    })()
    """#
    static let waitForImages = #"""
    const deadline = Date.now() + 1500;
    while (Date.now() < deadline) {
      if ([...document.querySelectorAll('img')].some(image => (image.currentSrc || image.src).startsWith('blob:'))) return;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    """#

    static let capture = #"""
    (() => {
      const host = location.hostname.toLowerCase();
      const snapshot = () => {
        const originals = document.querySelectorAll('img');
        originals.forEach(image => {
          if (!image.hasAttribute('data-yyreader-node')) {
            globalThis.__yyreaderNodeCounter = (globalThis.__yyreaderNodeCounter || 0) + 1;
            image.setAttribute('data-yyreader-node', String(globalThis.__yyreaderNodeCounter));
          }
        });
        const root = document.documentElement.cloneNode(true);
        const copies = root.querySelectorAll('img');
        originals.forEach((image, index) => {
          if (image.currentSrc.startsWith('blob:')) copies[index].setAttribute('src', image.currentSrc);
          // Read already-loaded sizes only; do not load offscreen pages for scoring.
          if (image.naturalWidth >= 160 && image.naturalHeight >= 160) {
            copies[index].setAttribute('data-yyreader-width', String(image.naturalWidth));
            copies[index].setAttribute('data-yyreader-height', String(image.naturalHeight));
          }
        });
        return root;
      };
      if (host === 'manhuazhan.com' || host.endsWith('.manhuazhan.com')) {
        // The normal site script has already decoded its public reader list.
        if (typeof newImgs === 'undefined' || !Array.isArray(newImgs))
          return snapshot().outerHTML;
        const imageURLs = newImgs.map(item => item && typeof item.url === 'string' ? item.url : null)
          .filter(value => value && /^https?:\/\//.test(value));
        const root = snapshot();
        const metadata = document.createElement('script');
        metadata.type = 'application/json';
        metadata.id = 'yyreader-manga-images';
        metadata.textContent = JSON.stringify({ imageURLs }).replace(/</g, '\\u003c');
        root.appendChild(metadata);
        return root.outerHTML;
      }
      const publicReader = host === 'haoduoman.com' || host.endsWith('.haoduoman.com')
        || host === 'duokanmh.com' || host.endsWith('.duokanmh.com');
      if (!publicReader) return snapshot().outerHTML;
      const config = typeof params === 'object' && params !== null ? params : null;
      if (!config || config.comic_status === 'down' || !Array.isArray(config.chapter_images))
        return snapshot().outerHTML;
      const hosts = Array.isArray(config.images_hosts) ? config.images_hosts : [];
      const base = hosts[0] || location.origin;
      const imageURLs = config.chapter_images.map(value => {
        if (typeof value !== 'string') return null;
        try { return new URL(value, base.endsWith('/') ? base : base + '/').href; }
        catch { return null; }
      }).filter(value => value && /^https?:\/\//.test(value));
      const root = snapshot();
      const metadata = document.createElement('script');
      metadata.type = 'application/json';
      metadata.id = 'yyreader-manga-images';
      metadata.textContent = JSON.stringify({ imageURLs, chapterTitle: config.chapter_title, bookTitle: config.comic_name, catalogURL: config.comic_url }).replace(/</g, '\\u003c');
      root.appendChild(metadata);
      return root.outerHTML;
    })()
    """#
}
