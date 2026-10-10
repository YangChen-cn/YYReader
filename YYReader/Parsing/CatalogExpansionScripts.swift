enum CatalogExpansionScripts {
    static let labels: Set<String> = ["展开完整列表", "展开完整目录", "展开全部章节", "加载全部章节", "加载更多章节"]

    // Only expand an explicit chapter-list control, never arbitrary buttons,
    // login controls or verification widgets. The returned DOM stays native-reader input.
    static let expand = """
    const normalize = text => text.replace(/[\\s\\[\\]【】]/g, '');
    const labels = new Set(['展开完整列表', '展开完整目录', '展开全部章节', '加载全部章节', '加载更多章节']);
    const count = () => [...document.querySelectorAll('a[href]')]
        .filter(a => /第.+[章回节節话話]/.test(a.textContent) ||
            /^\\/(?:chapter|read)\\//.test(new URL(a.href, location.href).pathname)).length;
    const initialCount = count();
    if (initialCount < 2) return false;
    const control = [...document.querySelectorAll('a, button')].find(element =>
        labels.has(normalize(element.textContent)) &&
        element.getClientRects().length > 0 &&
        (element.tagName === 'BUTTON' && element.type === 'button' ||
         (element.getAttribute('href') || '').toLowerCase().startsWith('javascript:')));
    if (!control) return false;
    control.click();
    const deadline = Date.now() + 8000;
    while (Date.now() < deadline) {
        await new Promise(resolve => setTimeout(resolve, 200));
        if (count() > initialCount) {
            control.setAttribute('data-yyreader-expanded', 'true');
            return true;
        }
    }
    return false;
    """
}
