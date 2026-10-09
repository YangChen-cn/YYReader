/// Capture only image addresses already made public by the website's normal reader.
/// WebKit remains a source of data, never the comic rendering surface.
enum MangaSnapshotScripts {
    static let capture = #"""
    (() => {
      const host = location.hostname.toLowerCase();
      if (!(host === 'haoduoman.com' || host.endsWith('.haoduoman.com')))
        return document.documentElement.outerHTML;
      const config = typeof params === 'object' && params !== null ? params : null;
      if (!config || config.comic_status === 'down' || !Array.isArray(config.chapter_images))
        return document.documentElement.outerHTML;
      const hosts = Array.isArray(config.images_hosts) ? config.images_hosts : [];
      const base = hosts[0] || location.origin;
      const imageURLs = config.chapter_images.map(value => {
        if (typeof value !== 'string') return null;
        try { return new URL(value, base.endsWith('/') ? base : base + '/').href; }
        catch { return null; }
      }).filter(value => value && /^https?:\/\//.test(value));
      const root = document.documentElement.cloneNode(true);
      const metadata = document.createElement('script');
      metadata.type = 'application/json';
      metadata.id = 'yyreader-manga-images';
      metadata.textContent = JSON.stringify({ imageURLs }).replace(/</g, '\\u003c');
      root.appendChild(metadata);
      return root.outerHTML;
    })()
    """#
}
