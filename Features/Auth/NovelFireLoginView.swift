import SwiftUI
import WebKit
import Combine

#if os(iOS)
typealias PlatformViewRepresentable = UIViewRepresentable
#else
typealias PlatformViewRepresentable = NSViewRepresentable
#endif

struct NovelFireLoginView: View {
    @Environment(\.dismiss) private var dismiss
    var onLoginSuccess: () -> Void
    /// Which LNW-family site to sign in to. Defaults to NovelFire for backwards compatibility.
    var site: CommentSite = .novelFire
    
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    var body: some View {
        ZStack {
            NovelFireWebViewWrapper(
                url: site.googleAuthURL,
                site: site,
                isLoading: $isLoading,
                errorMessage: $errorMessage,
                onSuccess: {
                    onLoginSuccess()
                    dismiss()
                }
            )
            .ignoresSafeArea(edges: .bottom)
            
            if isLoading {
                ProgressView("Loading Google Sign-in...")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            
            if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        errorMessage = nil
                        isLoading = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(iOS)
                .background(Color(.systemBackground))
                #else
                .background(Color(.windowBackgroundColor))
                #endif
            }
        }
        .navigationTitle("Sign In to \(site.displayName)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct NovelFireWebViewWrapper: PlatformViewRepresentable {
    let url: URL
    var site: CommentSite = .novelFire
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    var onSuccess: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView {
        return createWebView(context: context)
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    #else
    func makeNSView(context: Context) -> WKWebView {
        return createWebView(context: context)
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    #endif
    
    private func createWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // Use a clean desktop Safari user agent to bypass Google disallowed_useragent OAuth block
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        
        // Wait for cookie store deletion to finish completely before loading the redirect URL
        let cookieStore = configuration.websiteDataStore.httpCookieStore
        let targetDomain = site.domain
        cookieStore.getAllCookies { cookies in
            let group = DispatchGroup()
            for cookie in cookies {
                if cookie.domain.contains(targetDomain) {
                    group.enter()
                    cookieStore.delete(cookie) {
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                // Clear from HTTPCookieStorage as well
                if let httpCookies = HTTPCookieStorage.shared.cookies {
                    for hc in httpCookies {
                        if hc.domain.contains(targetDomain) {
                            HTTPCookieStorage.shared.deleteCookie(hc)
                        }
                    }
                }
                
                // Now load the URL safely
                let request = URLRequest(url: url)
                webView.load(request)
            }
        }
        
        return webView
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: NovelFireWebViewWrapper
        
        init(parent: NovelFireWebViewWrapper) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
            checkCookies(webView: webView)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.errorMessage = error.localizedDescription
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.errorMessage = error.localizedDescription
            }
        }
        
        private func checkCookies(webView: WKWebView) {
            guard let url = webView.url else { return }
            let urlString = url.absoluteString
            let site = parent.site

            // Only dismiss if we are back on the site's pages and it's not the initial redirect redirecting to Google
            if urlString.contains(site.domain) && !urlString.contains("auth/redirect/google") {
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    let hasSession = cookies.contains { $0.name == site.sessionCookieName }
                    if hasSession {
                        DispatchQueue.main.async {
                            for cookie in cookies {
                                if cookie.domain.contains(site.domain) {
                                    HTTPCookieStorage.shared.setCookie(cookie)
                                }
                            }
                            self.parent.onSuccess()
                        }
                    }
                }
            }
        }
    }
}
