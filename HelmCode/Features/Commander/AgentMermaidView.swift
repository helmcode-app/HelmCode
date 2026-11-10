//
//  AgentMermaidView.swift
//  HelmCode
//
//  Renders ```mermaid fences via WKWebView + Mermaid CDN, with source fallback.
//

import SwiftUI
import WebKit

struct AgentMermaidView: View {
    let source: String
    let colorScheme: ColorScheme

    @State private var height: CGFloat = 64
    @State private var renderFailed = false
    @State private var showSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(AgentChrome.hairline(colorScheme))
                .frame(height: 1)
                .accessibilityHidden(true)

            if showSource || renderFailed {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(source.isEmpty ? " " : source)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            } else {
                AgentMermaidWebView(
                    source: source,
                    colorScheme: colorScheme,
                    height: $height,
                    onFailed: { renderFailed = true }
                )
                .frame(height: height)
                .frame(maxWidth: .infinity)
            }
        }
        .background(
            AgentChrome.codeFill,
            in: RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous)
                .strokeBorder(AgentChrome.hairline(colorScheme), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("mermaid")
                .font(.caption2.weight(.bold).monospaced())
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 4)
            if renderFailed {
                Text("Render failed")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Button {
                showSource.toggle()
            } label: {
                Text(showSource ? "Diagram" : "Source")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showSource ? "Show diagram" : "Show source")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - WKWebView bridge

private struct AgentMermaidWebView: UIViewRepresentable {
    let source: String
    let colorScheme: ColorScheme
    @Binding var height: CGFloat
    var onFailed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, onFailed: onFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let user = WKUserContentController()
        user.add(context.coordinator, name: "helmMermaid")
        config.userContentController = user

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.height = $height
        context.coordinator.onFailed = onFailed
        let key = source + "|" + (colorScheme == .dark ? "dark" : "light")
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        webView.loadHTMLString(
            Self.html(source: source, dark: colorScheme == .dark),
            baseURL: URL(string: "https://cdn.jsdelivr.net/")
        )
    }

    static func html(source: String, dark: Bool) -> String {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let bg = dark ? "#1c1c1e" : "#f2f2f7"
        let fg = dark ? "#e5e5ea" : "#1c1c1e"
        let theme = dark ? "dark" : "default"
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
          <style>
            html, body {
              margin: 0; padding: 8px;
              background: \(bg); color: \(fg);
              overflow: hidden;
              height: auto;
            }
            #stage {
              width: 100%;
              display: flex;
              justify-content: center;
              align-items: center;
            }
            #stage svg {
              max-width: 100% !important;
              height: auto !important;
              display: block;
            }
            .error {
              font: 12px -apple-system, sans-serif;
              color: #ff9f0a; white-space: pre-wrap;
            }
          </style>
          <script type="module">
            import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
            const post = (type, payload = {}) => {
              try {
                window.webkit.messageHandlers.helmMermaid.postMessage({ type, ...payload });
              } catch (_) {}
            };
            const reportHeight = () => {
              const svg = document.querySelector('#stage svg');
              let h = 0;
              if (svg) {
                const rect = svg.getBoundingClientRect();
                // 16px is total vertical padding (8px top + 8px bottom)
                h = Math.ceil(rect.height + 16);
              } else {
                h = Math.ceil(Math.max(
                  document.documentElement.scrollHeight,
                  document.body.scrollHeight
                ));
              }
              if (h > 0) {
                post('height', { height: h });
              }
            };
            try {
              mermaid.initialize({
                startOnLoad: false,
                theme: '\(theme)',
                securityLevel: 'strict',
                fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
              });
              const def = `\(escaped)`;
              const { svg } = await mermaid.render('helmMermaidSvg', def);
              document.getElementById('stage').innerHTML = svg;
              reportHeight();
              requestAnimationFrame(reportHeight);
              setTimeout(reportHeight, 60);
              setTimeout(reportHeight, 200);
            } catch (err) {
              document.getElementById('stage').innerHTML =
                '<div class="error">Mermaid render error</div>';
              post('error', { message: String(err) });
            }
          </script>
        </head>
        <body>
          <div id="stage"></div>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var onFailed: () -> Void
        var loadedKey: String?
        weak var webView: WKWebView?

        init(height: Binding<CGFloat>, onFailed: @escaping () -> Void) {
            self.height = height
            self.onFailed = onFailed
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            switch type {
            case "height":
                let rawValue: CGFloat? = (body["height"] as? CGFloat)
                    ?? (body["height"] as? Double).map { CGFloat($0) }
                if let value = rawValue {
                    let next = min(max(value, 36), 1200)
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            self.height.wrappedValue = next
                        }
                    }
                }
            case "error":
                DispatchQueue.main.async { self.onFailed() }
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            DispatchQueue.main.async { self.onFailed() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.onFailed() }
        }
    }
}
