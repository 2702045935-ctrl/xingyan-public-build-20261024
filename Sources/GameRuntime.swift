import UIKit
import WebKit

enum GameRuntimeAssets {
    static func download(_ files: [String],
                         from remoteDir: URL,
                         to root: URL,
                         force: Bool) async throws {
        let fm = FileManager.default
        var pending: [String] = []
        pending.reserveCapacity(files.count)
        for file in files {
            let destination = root.appendingPathComponent(file)
            if !force,
               let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > 0 {
                continue
            }
            pending.append(file)
        }

        let window = 4
        for start in stride(from: 0, to: pending.count, by: window) {
            let end = min(pending.count, start + window)
            let batch = Array(pending[start..<end])
            try await withThrowingTaskGroup(of: Void.self) { group in
                for file in batch {
                    group.addTask {
                        let destination = root.appendingPathComponent(file)
                        try fm.createDirectory(
                            at: destination.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        let data = try await API.shared.assetData(
                            remoteDir.appendingPathComponent(file)
                        )
                        try data.write(to: destination, options: .atomic)
                    }
                }
                try await group.waitForAll()
            }
        }
    }
}

@MainActor
enum GameRuntimeConfiguration {
    private static let processPool = WKProcessPool()

    static func make() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = processPool
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.suppressesIncrementalRendering = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: WebSafeArea.js,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: GameRuntimeJavaScript.performance,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        return configuration
    }

    static func configure(_ webView: WKWebView,
                          background: UIColor = UIColor(red: 0.043,
                                                        green: 0.055,
                                                        blue: 0.090,
                                                        alpha: 1)) {
        webView.isOpaque = true
        webView.backgroundColor = background
        webView.underPageBackgroundColor = background
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.isMultipleTouchEnabled = true

        let scroll = webView.scrollView
        scroll.backgroundColor = background
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bounces = false
        scroll.alwaysBounceVertical = false
        scroll.alwaysBounceHorizontal = false
        scroll.isScrollEnabled = false
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = false
    }
}

@MainActor
enum GameRuntimeWarmup {
    private static var holder: WKWebView?

    static func warm() {
        guard holder == nil else { return }
        let web = WKWebView(frame: .zero, configuration: GameRuntimeConfiguration.make())
        GameRuntimeConfiguration.configure(web)
        web.loadHTMLString(
            """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>html,body{margin:0;background:#0b0e17;overflow:hidden}</style></head>
            <body><canvas id="warm" width="2" height="2"></canvas>
            <script>
            try { document.getElementById('warm').getContext('webgl2') ||
                  document.getElementById('warm').getContext('webgl'); } catch (e) {}
            </script></body></html>
            """,
            baseURL: nil
        )
        holder = web
    }
}

enum GameRuntimeJavaScript {
    static let performance = """
    (() => {
      'use strict';
      if (window.__chrisGameRuntime) return;
      window.__chrisGameRuntime = true;

      const capDpr = 2;
      const nativeDpr = Number(window.devicePixelRatio) || 1;
      if (nativeDpr > capDpr) {
        try {
          Object.defineProperty(window, 'devicePixelRatio', {
            configurable: true,
            get: () => capDpr
          });
        } catch (e) {}
      }

      const nativeGetContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function(type, options) {
        const kind = String(type || '').toLowerCase();
        options = Object.assign({}, options || {});
        if (kind === '2d') {
          if (options.alpha === undefined) options.alpha = false;
          if (options.desynchronized === undefined) options.desynchronized = true;
        } else if (kind === 'webgl' || kind === 'webgl2' ||
                   kind === 'experimental-webgl') {
          if (options.alpha === undefined) options.alpha = false;
          if (options.antialias === undefined) options.antialias = false;
          if (options.depth === undefined) options.depth = true;
          if (options.powerPreference === undefined) {
            options.powerPreference = 'high-performance';
          }
          if (options.desynchronized === undefined) {
            options.desynchronized = true;
          }
          if (options.preserveDrawingBuffer === undefined) {
            options.preserveDrawingBuffer = false;
          }
        }
        return nativeGetContext.call(this, type, options);
      };

      const installStyle = () => {
        if (!document.documentElement || document.getElementById('__chris_runtime_style')) {
          return;
        }
        const style = document.createElement('style');
        style.id = '__chris_runtime_style';
        style.textContent = [
          'html,body{overscroll-behavior:none;touch-action:none;',
          '-webkit-user-select:none;user-select:none;',
          '-webkit-tap-highlight-color:transparent;background:#0b0e17;',
          'overflow:hidden}',
          'canvas{display:block;touch-action:none;outline:none}',
          '*{-webkit-touch-callout:none}'
        ].join('');
        (document.head || document.documentElement).appendChild(style);
      };

      installStyle();
      document.addEventListener('DOMContentLoaded', installStyle, { once: true });
      document.addEventListener('gesturestart', event => event.preventDefault(),
                                { passive: false });
      document.addEventListener('dblclick', event => event.preventDefault(),
                                { passive: false });
    })();
    """
}
