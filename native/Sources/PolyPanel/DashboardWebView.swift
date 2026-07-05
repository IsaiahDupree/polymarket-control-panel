import SwiftUI
import WebKit

/// WKWebView wrapper — the whole dashboard UI lives in the served HTML,
/// so web and native stay pixel-identical.
struct DashboardWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.setValue(false, forKey: "drawsBackground") // let SwiftUI bg show while loading
        wv.navigationDelegate = context.coordinator
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let url: URL
        init(url: URL) { self.url = url }

        // Backend may still be booting — retry until it answers.
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { retry(webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { retry(webView) }
        private func retry(_ webView: WKWebView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [url] in
                webView.load(URLRequest(url: url))
            }
        }
    }
}
