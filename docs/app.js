/**
 * YYReader Official Website Interactive Controller
 */

document.addEventListener('DOMContentLoaded', () => {
  initThemeToggle();
  initOsDetection();
  initShowcaseTabs();
  initReaderSandbox();
  initFaqAccordion();
  initCopyButtons();
  initMobileMenu();
  initScrollSpy();
});

/* ==========================================================================
   1. Theme Toggle (Site-wide Light / Dark)
   ========================================================================== */
function initThemeToggle() {
  const themeToggleBtn = document.getElementById('themeToggleBtn');
  const body = document.body;

  // Retrieve saved or system preference
  const savedTheme = localStorage.getItem('yyreader_site_theme');
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

  const initialTheme = savedTheme || (prefersDark ? 'dark' : 'light');
  setTheme(initialTheme);

  if (themeToggleBtn) {
    themeToggleBtn.addEventListener('click', () => {
      const currentTheme = body.getAttribute('data-theme') || 'light';
      const nextTheme = currentTheme === 'dark' ? 'light' : 'dark';
      setTheme(nextTheme);
      localStorage.setItem('yyreader_site_theme', nextTheme);
    });
  }

  function setTheme(theme) {
    body.setAttribute('data-theme', theme);
  }
}

/* ==========================================================================
   2. OS Detection & Dynamic Download CTA
   ========================================================================== */
function initOsDetection() {
  const userAgent = navigator.userAgent || '';
  const platform = navigator.platform || '';

  const isWindows = /Win/i.test(platform) || /Windows/i.test(userAgent);
  const isMac = /Mac/i.test(platform) || /Macintosh/i.test(userAgent);

  const primaryBtn = document.getElementById('primaryDownloadBtn');
  const primaryLabel = document.getElementById('primaryDownloadLabel');
  const primarySub = document.getElementById('primaryDownloadSub');
  const primaryIcon = document.getElementById('primaryOsIcon');
  const heroImage = document.getElementById('heroDisplayImage');
  const heroTitle = document.getElementById('windowFrameTitle');

  if (isWindows && primaryBtn && primaryLabel && primarySub && primaryIcon) {
    // Customize for Windows
    primaryBtn.href = 'https://github.com/YangChen-cn/YYReader/releases/download/v1.2.3/YYReader-Setup-x64-1.2.3.exe';
    primaryLabel.textContent = '下载 Windows 版 (x64 安装包)';
    primarySub.textContent = '64 位 Windows 10/11 • v1.2.3';

    // Windows Icon SVG
    primaryIcon.innerHTML = `<path d="M0 3.449L9.75 2.1v9.451H0m10.949-9.602L24 0v11.4H10.949M0 12.6h9.75v9.451L0 20.699M10.949 12.6H24V24l-12.9-1.801"/>`;

    if (heroImage && heroTitle) {
      heroImage.src = 'images/yyreader-windows-library.png';
      heroImage.alt = 'YYReader Windows 客户端主界面展示';
      heroTitle.textContent = 'YYReader - Windows 现代目录与阅读界面';
    }
  } else if (isMac && primaryBtn) {
    // Already defaults to macOS in HTML
  }
}

/* ==========================================================================
   3. Platform Showcase Tabs
   ========================================================================== */
const showcaseData = {
  'macos-lib': {
    image: 'images/yyreader-macos-library.png',
    badge: 'macOS 15+ 原生界面',
    title: '三栏式书架与目录结构',
    desc: '经典 macOS 原生 NavigationSplitView 三栏布局，左侧书架列表一目了然，中间完整章节目录支持即时搜索与过滤，右侧纯净原生正文预览。',
    highlights: [
      '支持 <code>⌘L</code> 快速添加章节 URL',
      '目录按网站实际出现顺序索引，智能去重',
      '支持单章与全本目录离线下载进度指示'
    ]
  },
  'macos-read': {
    image: 'images/yyreader-macos-reading-settings.png',
    badge: 'SwiftUI 原生渲染',
    title: '沉浸阅读与精细排版调节',
    desc: '全屏与沉浸阅读模式，实时调节多款高品质阅读主题（默认、羊皮纸、夜读等）、自定义字体、字号、行距、段距与段首缩进。',
    highlights: [
      '原生 <code>ScrollView</code> + <code>LazyVStack</code> 虚拟滚动',
      '后续 3 章后台无感预取与 Single-Flight 防重机制',
      '滚动 Anchor 智能记忆，杜绝跳页回滚'
    ]
  },
  'win-lib': {
    image: 'images/yyreader-windows-library.png',
    badge: 'Windows 10/11 原生体验',
    title: 'WinUI 3 现代可收起目录',
    desc: '采用 Windows 现代 Fluent 设计语言，左侧章节列表支持快速折叠/展开与定位，正文滚动时自动将当前章置于居中视野。',
    highlights: [
      '自包含独立安装包，无需额外配置 .NET 运行库',
      '章节列表平滑居中滚动与搜索过滤',
      '与 macOS 端数据模型和通用解析规则完全对齐'
    ]
  },
  'win-read': {
    image: 'images/yyreader-windows-reading-settings.png',
    badge: 'WinUI 3 原生文本',
    title: '灵活自如的版式与主题定制',
    desc: '支持沉浸式工具栏与丰富排版参数配置，提供多款护眼色彩主题，配合键盘方向键与翻页键实现丝滑连读。',
    highlights: [
      'WinUI 原生文本渲染，零 WebView 滞涩',
      '原地无感双向同步 <code>windows.json</code>',
      '支持按需单章与全书离线持久化缓存'
    ]
  }
};

function initShowcaseTabs() {
  const tabs = document.querySelectorAll('.showcase-tab');
  const imgElem = document.getElementById('showcaseImage');
  const badgeElem = document.getElementById('showcaseBadge');
  const titleElem = document.getElementById('showcaseTitle');
  const descElem = document.getElementById('showcaseDesc');
  const highlightsElem = document.getElementById('showcaseHighlights');

  if (!tabs.length || !imgElem) return;

  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      tabs.forEach(t => {
        t.classList.remove('active');
        t.setAttribute('aria-selected', 'false');
      });
      tab.classList.add('active');
      tab.setAttribute('aria-selected', 'true');

      const target = tab.getAttribute('data-target');
      const data = showcaseData[target];
      if (!data) return;

      // Smooth cross-fade
      imgElem.style.opacity = '0.3';
      setTimeout(() => {
        imgElem.src = data.image;
        imgElem.style.opacity = '1';
        badgeElem.textContent = data.badge;
        titleElem.textContent = data.title;
        descElem.textContent = data.desc;

        highlightsElem.innerHTML = data.highlights.map(item => `
          <div class="highlight-item">
            <span class="item-check">✓</span>
            <span>${item}</span>
          </div>
        `).join('');
      }, 150);
    });
  });
}

/* ==========================================================================
   4. Interactive Reader Sandbox
   ========================================================================== */
function initReaderSandbox() {
  const viewport = document.getElementById('readerViewport');
  const paperSheet = document.getElementById('readerPaperSheet');
  const themeChips = document.querySelectorAll('.theme-chip');
  const fontToggles = document.querySelectorAll('.btn-toggle');
  const fontDecBtn = document.getElementById('fontDecBtn');
  const fontIncBtn = document.getElementById('fontIncBtn');
  const fontSizeVal = document.getElementById('fontSizeVal');
  const widthBtns = [
    { btn: document.getElementById('widthNarrowBtn'), cls: 'width-narrow' },
    { btn: document.getElementById('widthNormalBtn'), cls: 'width-normal' },
    { btn: document.getElementById('widthWideBtn'), cls: 'width-wide' }
  ];

  if (!viewport || !paperSheet) return;

  // 1. Theme Chips
  themeChips.forEach(chip => {
    chip.addEventListener('click', () => {
      themeChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');

      const theme = chip.getAttribute('data-reader-theme');
      viewport.className = `reader-viewport theme-${theme}`;
    });
  });

  // 2. Font Style
  fontToggles.forEach(toggle => {
    toggle.addEventListener('click', () => {
      fontToggles.forEach(t => t.classList.remove('active'));
      toggle.classList.add('active');

      const font = toggle.getAttribute('data-font');
      if (font === 'serif') {
        paperSheet.classList.add('font-serif');
        paperSheet.classList.remove('font-sans');
      } else {
        paperSheet.classList.add('font-sans');
        paperSheet.classList.remove('font-serif');
      }
    });
  });

  // 3. Font Size Stepper
  let currentFontSize = 18;
  const minFontSize = 14;
  const maxFontSize = 26;

  function updateFontSize(newSize) {
    currentFontSize = Math.min(Math.max(newSize, minFontSize), maxFontSize);
    document.documentElement.style.setProperty('--sandbox-font-size', `${currentFontSize}px`);
    if (fontSizeVal) fontSizeVal.textContent = `${currentFontSize}px`;
  }

  if (fontDecBtn) fontDecBtn.addEventListener('click', () => updateFontSize(currentFontSize - 1));
  if (fontIncBtn) fontIncBtn.addEventListener('click', () => updateFontSize(currentFontSize + 1));

  // 4. Width Options
  widthBtns.forEach(item => {
    if (!item.btn) return;
    item.btn.addEventListener('click', () => {
      widthBtns.forEach(w => w.btn && w.btn.classList.remove('active'));
      item.btn.classList.add('active');

      paperSheet.classList.remove('width-narrow', 'width-normal', 'width-wide');
      paperSheet.classList.add(item.cls);
    });
  });
}

/* ==========================================================================
   5. FAQ Accordion
   ========================================================================== */
function initFaqAccordion() {
  const faqItems = document.querySelectorAll('.faq-item');

  faqItems.forEach(item => {
    const questionBtn = item.querySelector('.faq-question');
    if (!questionBtn) return;

    questionBtn.addEventListener('click', () => {
      const isOpen = item.classList.contains('open');

      // Close all other items
      faqItems.forEach(other => {
        if (other !== item) other.classList.remove('open');
      });

      // Toggle current
      if (isOpen) {
        item.classList.remove('open');
      } else {
        item.classList.add('open');
      }
    });
  });
}

/* ==========================================================================
   6. Copy Checksum to Clipboard & Toast
   ========================================================================== */
function initCopyButtons() {
  const copyBtns = document.querySelectorAll('.copy-btn');
  const toast = document.getElementById('toast');

  copyBtns.forEach(btn => {
    btn.addEventListener('click', async () => {
      const textToCopy = btn.getAttribute('data-copy');
      if (!textToCopy) return;

      try {
        await navigator.clipboard.writeText(textToCopy);
        showToast('SHA-256 校验码已复制到剪贴板！');
      } catch (err) {
        // Fallback
        const textarea = document.createElement('textarea');
        textarea.value = textToCopy;
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand('copy');
        document.body.removeChild(textarea);
        showToast('SHA-256 校验码已复制到剪贴板！');
      }
    });
  });

  function showToast(msg) {
    if (!toast) return;
    toast.textContent = msg;
    toast.classList.add('show');
    setTimeout(() => {
      toast.classList.remove('show');
    }, 2500);
  }
}

/* ==========================================================================
   7. Mobile Menu
   ========================================================================== */
function initMobileMenu() {
  const menuBtn = document.getElementById('mobileMenuBtn');
  const navLinks = document.getElementById('navLinks');

  if (!menuBtn || !navLinks) return;

  menuBtn.addEventListener('click', () => {
    navLinks.classList.toggle('open');
  });

  // Close menu when clicking any link
  navLinks.querySelectorAll('.nav-link').forEach(link => {
    link.addEventListener('click', () => {
      navLinks.classList.remove('open');
    });
  });
}

/* ==========================================================================
   8. Scroll Spy for Active Navigation
   ========================================================================== */
function initScrollSpy() {
  const sections = document.querySelectorAll('section[id]');
  const navLinks = document.querySelectorAll('.nav-link');

  window.addEventListener('scroll', () => {
    let currentId = '';
    const scrollPos = window.scrollY + 100;

    sections.forEach(section => {
      const sectionTop = section.offsetTop;
      const sectionHeight = section.offsetHeight;
      if (scrollPos >= sectionTop && scrollPos < sectionTop + sectionHeight) {
        currentId = section.getAttribute('id');
      }
    });

    navLinks.forEach(link => {
      link.classList.remove('active');
      if (link.getAttribute('href') === `#${currentId}`) {
        link.classList.add('active');
      }
    });
  });
}
