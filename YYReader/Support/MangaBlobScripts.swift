/// Reads a single image already displayed by the normal public reader. It never
/// decrypts data, makes CDN requests, or exports the whole chapter as base64.
enum MangaBlobScripts {
    /// Cheap affirmation before a full re-score: is the node resolved earlier
    /// still present and still showing the same source? Returns that source, or
    /// null when the node is gone, which falls back to re-scoring the document.
    static let confirmNode = #"""
    (() => {
      const node = [...document.querySelectorAll('img')].find(image => image.getAttribute('data-yyreader-node') === nodeID);
      return node ? (node.currentSrc || node.src || '') : null;
    })()
    """#
    static let readImage = #"""
    const normalized = value => { const u = new URL(value, location.href); u.hash = ''; return u.href; };
    const expectedChapter = normalized(chapterURL);
    globalThis.__yyreaderImageRequest = requestID;
    const deadline = Date.now() + 12000;
    while (Date.now() < deadline) {
      if (globalThis.__yyreaderImageRequest !== requestID) throw new Error('Cancelled image request');
      if (normalized(location.href) !== expectedChapter) throw new Error('Chapter changed');
      let image;
      if (domIndex >= 0) {
        image = nodeID ? [...document.querySelectorAll('img')].find(node => node.getAttribute('data-yyreader-node') === nodeID)
          : document.querySelectorAll('img')[domIndex];
        if (nodeID && !image) throw new Error('Image element replaced');
        if (expectedBlobURL && (image?.currentSrc || image?.src) !== expectedBlobURL) throw new Error('Image changed');
      } else {
      const config = typeof params === 'object' && params !== null ? params : null;
      if (config && config.comic_status === 'down') throw new Error('Chapter unavailable');
      if (config && Array.isArray(config.chapter_images)) {
        const base = (Array.isArray(config.images_hosts) && config.images_hosts[0]) || location.origin;
        const addresses = config.chapter_images.map(value =>
          typeof value === 'string' ? normalized(new URL(value, base.endsWith('/') ? base : base + '/').href) : null);
        const requested = new URL(imageURL);
        const index = addresses.findIndex(value => value === normalized(imageURL)
          || (value && /\.(?:jpe?g|png|webp|avif|gif)$/i.test(requested.pathname)
              && new URL(value).pathname === requested.pathname));
        if (index < 0) throw new Error('Image outside chapter');
        const container = document.querySelector('.chapter-images');
        const images = container ? [...container.querySelectorAll('img')] : [];
        image = images.find(node => node.parentElement?.getAttribute('data-index') === String(index))
          || (images.length === addresses.length ? images[index] : null);
      }
      }
      if (image && !(image.currentSrc || image.src).startsWith('blob:')) image.scrollIntoView({ block: 'center' });
      if (image && (image.currentSrc || image.src).startsWith('blob:') && image.naturalWidth > 0 && image.naturalHeight > 0) {
          const blobURL = image.currentSrc || image.src;
          const response = await fetch(blobURL);
          const blob = await response.blob();
          if (!response.ok || blob.size === 0 || blob.size > 30 * 1024 * 1024) throw new Error('Invalid image');
          const dataURL = await new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(new Error('Cannot read displayed image'));
            reader.readAsDataURL(blob);
          });
          if (globalThis.__yyreaderImageRequest !== requestID || normalized(location.href) !== expectedChapter ) throw new Error('Chapter changed');
          if ((image.currentSrc || image.src) !== blobURL) throw new Error('Image changed');
          return dataURL.substring(dataURL.indexOf(',') + 1);
      }
      await new Promise(resolve => setTimeout(resolve, 150));
    }
    throw new Error('Displayed image timed out');
    """#
}
