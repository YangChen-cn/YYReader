/* ==========================================================================
   YYReader 官网交互
   无依赖、无构建：主题、平台选择、截图切换、排版试读、复制校验值、滚动效果。
   ========================================================================== */
(function () {
  "use strict";

  var root = document.documentElement;
  var store = {
    get: function (key, fallback) {
      try {
        var value = window.localStorage.getItem(key);
        return value === null ? fallback : value;
      } catch (error) {
        return fallback;
      }
    },
    set: function (key, value) {
      try {
        window.localStorage.setItem(key, value);
      } catch (error) {
        /* 隐私模式下忽略即可 */
      }
    }
  };

  /* ---------- 平台数据 ---------- */
  var PLATFORMS = {
    macos: {
      name: "macOS",
      label: "下载 macOS 版",
      meta: "arm64 DMG · 6.2 MB · 1.4.1",
      href: "https://github.com/YangChen-cn/YYReader/releases/download/v1.4.1/YYReader-1.4.1-arm64.dmg",
      frame: "macos",
      shots: [
        { src: "images/yyreader-macos-library.png", title: "YYReader · 书架、目录与正文并排", alt: "YYReader macOS 界面：书架、目录与正文并排" },
        { src: "images/yyreader-macos-reading-settings.png", title: "YYReader · 阅读设置", alt: "YYReader macOS 阅读设置：主题、字体与版式" }
      ]
    },
    ios: {
      name: "iPhone / iPad",
      label: "下载 iPhone / iPad 版",
      meta: "IPA · 7.4 MB · 1.4.1",
      href: "https://github.com/YangChen-cn/YYReader/releases/download/ios-v1.4.1/YYReader-iOS-1.4.1-resign.ipa",
      frame: "ios",
      shots: [
        { src: "images/yyreader-ios-bookshelf.png", title: "YYReader · iPhone 书架", alt: "iPhone 书架：书封、作者、离线状态与阅读进度" },
        { src: "images/yyreader-ios-reading.png", title: "YYReader · iPhone 阅读", alt: "iPhone 正文阅读：原生排版与章节菜单" },
        { src: "images/yyreader-ios-import-menu.png", title: "YYReader · 添加菜单", alt: "iOS 添加菜单：添加网页、导入 TXT 与书架传输" }
      ]
    },
    windows: {
      name: "Windows",
      label: "下载 Windows 版",
      meta: "x64 安装程序 · 45.6 MB · 1.3.0",
      href: "https://github.com/YangChen-cn/YYReader/releases/download/v1.3.0/YYReader-Setup-x64-1.3.0.exe",
      frame: "macos",
      shots: [
        { src: "images/yyreader-windows-library.png", title: "YYReader · Windows 目录与正文", alt: "Windows 章节目录与正文阅读" },
        { src: "images/yyreader-windows-reading-settings.png", title: "YYReader · Windows 阅读设置", alt: "Windows 阅读设置：字体、间距与宽度" }
      ]
    }
  };

  function detectPlatform() {
    var ua = navigator.userAgent || "";
    var touch = navigator.maxTouchPoints || 0;
    if (/iPhone|iPad|iPod/.test(ua) || (ua.indexOf("Mac") > -1 && touch > 1)) return "ios";
    if (/Win/.test(ua)) return "windows";
    return "macos";
  }

  /* ---------- 下载平台选择 ---------- */
  var picker = document.querySelector(".download-picker");
  var downloadBtn = document.getElementById("heroDownload");
  var downloadLabel = document.getElementById("heroDownloadLabel");
  var downloadMeta = document.getElementById("heroDownloadMeta");
  var frame = document.getElementById("deviceFrame");
  var frameTitle = document.getElementById("frameTitle");
  var stageImage = document.getElementById("stageImage");
  var thumbBar = document.getElementById("stageThumbs");
  var activePlatform = detectPlatform();
  var activeShot = 0;

  function renderThumbs() {
    var shots = PLATFORMS[activePlatform].shots;
    thumbBar.innerHTML = "";
    if (shots.length < 2) return;
    shots.forEach(function (shot, index) {
      var button = document.createElement("button");
      button.type = "button";
      button.className = index === activeShot ? "is-active" : "";
      button.setAttribute("aria-label", shot.title);
      button.innerHTML = '<img src="' + shot.src + '" alt="" loading="lazy">';
      button.addEventListener("click", function () {
        activeShot = index;
        renderThumbs();
      });
      thumbBar.appendChild(button);
    });
  }

  function renderStage() {
    var platform = PLATFORMS[activePlatform];
    var shot = platform.shots[activeShot] || platform.shots[0];
    stageImage.src = shot.src;
    stageImage.alt = shot.alt;
    frameTitle.textContent = shot.title;
    frame.dataset.device = platform.frame;
    renderThumbs();
  }

  function selectPlatform(key, remember) {
    if (!PLATFORMS[key]) return;
    activePlatform = key;
    activeShot = 0;
    var platform = PLATFORMS[key];
    if (downloadBtn) {
      downloadBtn.href = platform.href;
      downloadLabel.textContent = platform.label;
      downloadMeta.textContent = platform.meta;
    }
    if (picker) {
      Array.prototype.forEach.call(picker.querySelectorAll(".pick"), function (button) {
        button.classList.toggle("is-active", button.dataset.platform === key);
      });
    }
    renderStage();
    if (remember) store.set("yyreader.platform", key);
  }

  if (downloadBtn && picker) {
    picker.addEventListener("click", function (event) {
      var button = event.target.closest(".pick");
      if (button) selectPlatform(button.dataset.platform, true);
    });
    selectPlatform(store.get("yyreader.platform", activePlatform), false);
  }

  /* ---------- 界面一览标签页 ---------- */
  var tabs = document.querySelectorAll(".tab");
  var panels = document.querySelectorAll(".panel");
  Array.prototype.forEach.call(tabs, function (tab) {
    tab.addEventListener("click", function () {
      Array.prototype.forEach.call(tabs, function (other) {
        var on = other === tab;
        other.classList.toggle("is-active", on);
        other.setAttribute("aria-selected", on ? "true" : "false");
      });
      Array.prototype.forEach.call(panels, function (panel) {
        panel.classList.toggle("is-active", panel.dataset.panel === tab.dataset.tab);
      });
    });
  });

  /* ---------- 主题 ---------- */
  var themeToggle = document.getElementById("themeToggle");

  function resolvedTheme() {
    var stored = store.get("yyreader.theme", "auto");
    if (stored !== "auto") return stored;
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  function applyTheme(mode) {
    root.dataset.theme = mode;
    store.set("yyreader.theme", mode);
    if (themeToggle) {
      themeToggle.setAttribute("aria-label", mode === "dark" ? "切换到浅色主题" : "切换到深色主题");
    }
  }

  applyTheme(store.get("yyreader.theme", "auto"));

  if (themeToggle) {
    themeToggle.addEventListener("click", function () {
      applyTheme(resolvedTheme() === "dark" ? "light" : "dark");
    });
  }

  /* ---------- 顶栏与移动菜单 ---------- */
  var header = document.getElementById("siteHeader");
  var nav = document.getElementById("siteNav");
  var menuToggle = document.getElementById("menuToggle");

  function onScroll() {
    if (header) header.classList.toggle("is-scrolled", window.scrollY > 8);
  }
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  if (menuToggle && nav) {
    menuToggle.addEventListener("click", function () {
      var open = nav.classList.toggle("is-open");
      menuToggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    nav.addEventListener("click", function (event) {
      if (event.target.tagName === "A") {
        nav.classList.remove("is-open");
        menuToggle.setAttribute("aria-expanded", "false");
      }
    });
  }

  /* ---------- 排版试读 ---------- */
  var reader = document.getElementById("readerViewport");
  var sheet = document.getElementById("readerSheet");
  var fontValue = document.getElementById("fontValue");
  var readerState = {
    theme: store.get("yyreader.readerTheme", "paper"),
    font: store.get("yyreader.readerFont", "serif"),
    size: parseInt(store.get("yyreader.readerSize", "18"), 10) || 18,
    width: store.get("yyreader.readerWidth", "normal")
  };

  function renderReader() {
    if (!reader || !sheet) return;
    reader.className = "reader theme-" + readerState.theme;
    sheet.className = "reader-sheet font-" + readerState.font + " width-" + readerState.width;
    sheet.style.setProperty("--reader-size", readerState.size + "px");
    sheet.style.setProperty("--reader-line", (1.55 + readerState.size / 100).toFixed(2) + "em");
    if (fontValue) fontValue.textContent = readerState.size + "px";
  }

  function markActive(container, attribute, value) {
    if (!container) return;
    Array.prototype.forEach.call(container.querySelectorAll("[" + attribute + "]"), function (node) {
      node.classList.toggle("is-active", node.getAttribute(attribute) === value);
    });
  }

  var themeChips = document.getElementById("themeChips");
  var fontToggle = document.getElementById("fontToggle");
  var widthToggle = document.getElementById("widthToggle");
  var fontDec = document.getElementById("fontDec");
  var fontInc = document.getElementById("fontInc");

  if (themeChips) {
    themeChips.addEventListener("click", function (event) {
      var chip = event.target.closest("[data-reader-theme]");
      if (!chip) return;
      readerState.theme = chip.dataset.readerTheme;
      store.set("yyreader.readerTheme", readerState.theme);
      markActive(themeChips, "data-reader-theme", readerState.theme);
      renderReader();
    });
  }

  if (fontToggle) {
    fontToggle.addEventListener("click", function (event) {
      var button = event.target.closest("[data-font]");
      if (!button) return;
      readerState.font = button.dataset.font;
      store.set("yyreader.readerFont", readerState.font);
      markActive(fontToggle, "data-font", readerState.font);
      renderReader();
    });
  }

  if (widthToggle) {
    widthToggle.addEventListener("click", function (event) {
      var button = event.target.closest("[data-width]");
      if (!button) return;
      readerState.width = button.dataset.width;
      store.set("yyreader.readerWidth", readerState.width);
      markActive(widthToggle, "data-width", readerState.width);
      renderReader();
    });
  }

  function stepFont(delta) {
    readerState.size = Math.min(30, Math.max(14, readerState.size + delta));
    store.set("yyreader.readerSize", String(readerState.size));
    renderReader();
  }
  if (fontDec) fontDec.addEventListener("click", function () { stepFont(-1); });
  if (fontInc) fontInc.addEventListener("click", function () { stepFont(1); });

  markActive(themeChips, "data-reader-theme", readerState.theme);
  markActive(fontToggle, "data-font", readerState.font);
  markActive(widthToggle, "data-width", readerState.width);
  renderReader();

  /* ---------- 复制校验值 ---------- */
  var toast = document.getElementById("toast");
  var toastTimer = null;

  function showToast(message) {
    if (!toast) return;
    toast.textContent = message;
    toast.classList.add("is-visible");
    window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(function () {
      toast.classList.remove("is-visible");
    }, 1800);
  }

  document.addEventListener("click", function (event) {
    var button = event.target.closest("[data-copy]");
    if (!button) return;
    var text = button.dataset.copy;

    function done(ok) {
      showToast(ok ? "已复制到剪贴板" : "复制失败，请手动选择");
    }

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(function () { done(true); }, function () { done(false); });
      return;
    }
    // file:// 或旧浏览器的兜底
    var area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (error) { ok = false; }
    document.body.removeChild(area);
    done(ok);
  });

  /* ---------- 滚动淡入与导航高亮 ---------- */
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var revealTargets = document.querySelectorAll(".section-head, .card, .package, .shortcut, .panel.is-active, .sync-files, .sync-points");

  if (!reduceMotion && "IntersectionObserver" in window) {
    Array.prototype.forEach.call(revealTargets, function (node) { node.classList.add("reveal"); });
    var revealObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          revealObserver.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    Array.prototype.forEach.call(revealTargets, function (node) { revealObserver.observe(node); });
  }

  var navLinks = document.querySelectorAll("#siteNav a[href^='#']");
  var sections = [];
  Array.prototype.forEach.call(navLinks, function (link) {
    var section = document.querySelector(link.getAttribute("href"));
    if (section) sections.push({ link: link, section: section });
  });

  if (sections.length && "IntersectionObserver" in window) {
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        Array.prototype.forEach.call(navLinks, function (link) { link.classList.remove("is-current"); });
        var match = sections.filter(function (item) { return item.section === entry.target; })[0];
        if (match) match.link.classList.add("is-current");
      });
    }, { rootMargin: "-45% 0px -50% 0px" });
    sections.forEach(function (item) { spy.observe(item.section); });
  }
})();
