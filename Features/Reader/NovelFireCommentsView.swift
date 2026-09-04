import SwiftUI
import WebKit
import Combine

#if os(iOS)
typealias CommentsPlatformRepresentable = UIViewRepresentable
#else
typealias CommentsPlatformRepresentable = NSViewRepresentable
#endif

struct NovelFireCommentsView: View {
    @Environment(\.dismiss) private var dismiss

    let postId: String
    let chapterId: String
    let csrfToken: String
    let chapterPath: String
    let backgroundColorHex: String
    let textColorHex: String
    /// Which LNW-family site these comments belong to.
    let site: CommentSite
    
    @State private var commentsHtml: String
    @State private var nextCursor: String?
    @State private var hasMoreComments: Bool
    @State private var showLoginSheet = false
    @State private var webViewBridge = CommentsWebViewBridge()
    
    init(
        postId: String,
        chapterId: String,
        csrfToken: String,
        initialCommentsHtml: String,
        initialNextCursor: String?,
        initialHasMore: Bool,
        chapterPath: String,
        backgroundColorHex: String,
        textColorHex: String,
        site: CommentSite = .novelFire
    ) {
        self.postId = postId
        self.chapterId = chapterId
        self.csrfToken = csrfToken
        self._commentsHtml = State(initialValue: initialCommentsHtml)
        self._nextCursor = State(initialValue: initialNextCursor)
        self._hasMoreComments = State(initialValue: initialHasMore)
        self.chapterPath = chapterPath
        self.backgroundColorHex = backgroundColorHex
        self.textColorHex = textColorHex
        self.site = site
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if postId.isEmpty && commentsHtml.isEmpty {
                    ProgressView("Loading comments...")
                } else if commentsHtml.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No comments on this chapter yet.")
                            .font(.headline)
                        Text("Be the first to say something on \(site.displayName)!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    CommentsWebViewWrapper(
                        html: commentsHTML(comments: commentsHtml),
                        bridge: webViewBridge,
                        onLoadMore: {
                            loadMoreComments()
                        },
                        onLike: { commentId in
                            handleLikeComment(commentId: commentId)
                        },
                        onDislike: { commentId in
                            handleDislikeComment(commentId: commentId)
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .navigationTitle("Chapter Comments")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showLoginSheet) {
                NovelFireLoginView(onLoginSuccess: {
                    // Success callback
                }, site: site)
            }
            .task {
                if postId.isEmpty || commentsHtml.isEmpty {
                    do {
                        let meta = try await NovelFireCommentsService.shared.fetchChapterMetadata(chapterPath: chapterPath, site: site)
                        let resolvedPostId = postId.isEmpty ? meta.postId : postId
                        let resolvedChapterId = chapterId.isEmpty ? meta.chapterId : chapterId

                        let response = try await NovelFireCommentsService.shared.fetchComments(postId: resolvedPostId, chapterId: resolvedChapterId, site: site)
                        self.commentsHtml = response.html
                        self.nextCursor = response.next_cursor
                        self.hasMoreComments = response.has_more_pages
                    } catch {
                        print("⚠️ Failed to load comments: \(error)")
                    }
                }
            }
        }
    }
    
    private func loadMoreComments() {
        guard let cursor = nextCursor else { return }
        let site = site
        Task {
            do {
                let response = try await NovelFireCommentsService.shared.fetchComments(
                    postId: postId,
                    chapterId: chapterId,
                    cursor: cursor,
                    site: site
                )

                self.commentsHtml += response.html
                self.nextCursor = response.next_cursor
                self.hasMoreComments = response.has_more_pages

                // Append via JavaScript in the webview (JSON-encoded to safely
                // handle quotes, newlines and emoji in comment HTML).
                let js = "window.appendComments(\(Self.jsString(response.html)), \(response.has_more_pages ? "true" : "false"));"
                _ = try? await webViewBridge.webView?.evaluateJavaScript(js)
            } catch {
                print("⚠️ Failed to load more comments: \(error)")
            }
        }
    }
    
    private func handleLikeComment(commentId: String) {
        handleCommentAction(commentId: commentId, isLike: true)
    }
    
    private func handleDislikeComment(commentId: String) {
        handleCommentAction(commentId: commentId, isLike: false)
    }
    
    private func handleCommentAction(commentId: String, isLike: Bool) {
        if !NovelFireCommentsService.shared.hasSession(for: site) {
            self.showLoginSheet = true
            return
        }

        let referer = site.referer(chapterPath: chapterPath)
        let site = site
        
        Task {
            do {
                let response: NovelFireCommentsService.ActionResponse
                if isLike {
                    response = try await NovelFireCommentsService.shared.likeComment(commentId: commentId, csrfToken: csrfToken, referer: referer, site: site)
                } else {
                    response = try await NovelFireCommentsService.shared.dislikeComment(commentId: commentId, csrfToken: csrfToken, referer: referer, site: site)
                }
                
                // Update UI in WebView
                let js = "window.updateCommentLikes(\"\(commentId)\", \(response.likes), \(response.dislikes), \(isLike ? "true" : "false"));"
                _ = try? await webViewBridge.webView?.evaluateJavaScript(js)
            } catch {
                print("⚠️ Action failed: \(error)")
            }
        }
    }
    
    private func commentsHTML(comments: String) -> String {
        // Respect the reader theme when provided; fall back to the previous
        // dark defaults so existing sheets look identical.
        let resolvedBg = backgroundColorHex.isEmpty ? "#0f0f0f" : backgroundColorHex
        let resolvedText = textColorHex.isEmpty ? "#f1f1f1" : textColorHex
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
        <style>
        :root {
            color-scheme: light dark;
        }
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            -webkit-user-select: none;
            user-select: none;
            -webkit-touch-callout: none;
        }
        .comment-text * {
            -webkit-user-select: text;
            user-select: text;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.4;
            padding: 16px 16px 40px;
            color: \(resolvedText);
            background: \(resolvedBg);
            -webkit-font-smoothing: antialiased;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        
        /* Comments Section CSS */
        #lnw-comments-section {
            padding: 0 0 2em;
        }
        .comment-wrapper ul {
            list-style: none;
            padding: 0;
            margin: 0;
        }
        .comment-wrapper > ul > li {
            background: transparent !important;
            border: none !important;
            box-shadow: none !important;
            border-bottom: 1px solid rgba(255, 255, 255, 0.08) !important;
            padding-bottom: 16px;
            margin-bottom: 16px;
        }
        .comment-wrapper > ul > li:last-child {
            border-bottom: none !important;
            padding-bottom: 0;
            margin-bottom: 0;
        }
        .comment-item {
            display: flex;
            flex-direction: column;
            gap: 4px;
        }
        .comment-header {
            display: flex;
            flex-direction: row;
            align-items: center;
            gap: 10px;
        }
        .user-avatar {
            width: 36px;
            height: 36px;
            border-radius: 50%;
            overflow: hidden;
            background: rgba(255, 255, 255, 0.1);
            flex-shrink: 0;
        }
        .user-avatar img.avatar {
            width: 100%;
            height: 100%;
            object-fit: cover;
            margin: 0;
            border-radius: 50%;
        }
        .user-info {
            display: flex;
            flex-direction: row;
            align-items: center;
            gap: 8px;
        }
        .head-items {
            display: flex;
            align-items: center;
        }
        .comment-header a, a.link-default, .username {
            text-decoration: none !important;
            color: #f1f1f1 !important;
            font-weight: 600;
            font-size: 13px;
        }
        .tier {
            font-size: 9px;
            background: rgba(255, 255, 255, 0.12);
            padding: 2px 6px;
            border-radius: 4px;
            color: #aaa;
            text-transform: uppercase;
            font-weight: 600;
            letter-spacing: 0.5px;
            margin-left: 2px;
        }
        .post-date {
            font-size: 12px;
            color: #aaa;
            margin-left: 4px;
        }
        .comment-body {
            margin-left: 46px; /* Width of avatar (36px) + gap (10px) */
            display: flex;
            flex-direction: column;
            gap: 4px;
        }
        .comment-text {
            font-size: 14px;
            color: #f1f1f1;
            line-height: 1.45;
            word-break: break-word;
        }
        .comment-text p {
            margin-bottom: 0.5em;
            text-align: left;
        }
        .comment-text p:last-child {
            margin-bottom: 0;
        }
        .comment-text[data-spoiler="1"] {
            background: rgba(128, 128, 128, 0.1);
            color: transparent !important;
            text-shadow: 0 0 8px rgba(128, 128, 128, 0.8);
            cursor: pointer;
            border-radius: 4px;
            padding: 4px 8px;
            user-select: none;
        }
        .comment-text[data-spoiler="1"] * {
            color: transparent !important;
        }
        .comment-text[data-spoiler="1"]::before {
            content: "Spoiler Warning (Tap to reveal)";
            display: block;
            color: #e53e3e !important;
            font-weight: bold;
            font-size: 12px;
            margin-bottom: 4px;
            text-shadow: none;
        }
        .comment-text[data-spoiler="1"].revealed {
            background: transparent;
            color: inherit !important;
            text-shadow: none;
            user-select: auto;
            padding: 0;
        }
        .comment-text[data-spoiler="1"].revealed * {
            color: inherit !important;
        }
        .comment-text[data-spoiler="1"].revealed::before {
            display: none;
        }
        .toolbar {
            display: flex;
            align-items: center;
            gap: 16px;
            margin-top: 4px;
            font-size: 12px;
            color: #aaa;
        }
        .toolbar a.reply {
            background: none;
            border: none;
            color: #aaa;
            font-family: inherit;
            font-size: 12px;
            font-weight: 500;
            cursor: pointer;
            padding: 4px 8px;
            border-radius: 12px;
            display: inline-flex;
            align-items: center;
            gap: 4px;
            text-decoration: none;
            transition: background 0.2s, color 0.2s;
        }
        .toolbar a.reply:hover {
            background: rgba(255, 255, 255, 0.1);
            color: #f1f1f1;
        }
        .toolbar .divider, .btn-report, .reportComment, button.btn-report {
            display: none !important;
        }
        .toolbar .spacer {
            margin-left: auto;
        }
        .usrlike {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .like-group, .dislike-group {
            display: flex;
            align-items: center;
        }
        .like-button, .dislike-button {
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 30px;
            height: 30px;
            border-radius: 50%;
            background: transparent !important;
            border: none !important;
            color: #aaa;
            transition: background 0.2s, color 0.2s, transform 0.1s;
        }
        .like-button:hover, .dislike-button:hover {
            background: rgba(255, 255, 255, 0.1) !important;
            color: #f1f1f1;
        }
        .like-button:active, .dislike-button:active {
            transform: scale(0.9);
        }
        .like-button.checked {
            color: #3182ce !important;
        }
        .dislike-button.checked {
            color: #e53e3e !important;
        }
        .reply-comments {
            margin-left: 48px;
            padding-left: 0;
            border-left: none;
            margin-top: 12px;
        }
        .reply-comments li.none, .reply-comments .none {
            display: none !important;
        }
        .reply-comments.expanded li.none, .reply-comments.expanded .none {
            display: flex !important;
        }
        .show_replies {
            list-style: none !important;
            margin-bottom: 8px !important;
        }
        .show_replies a {
            color: #3182ce;
            font-size: 13px;
            font-weight: 500;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 6px;
        }
        .show_replies a:hover {
            text-decoration: underline;
        }
        .parent-link {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            font-size: 11px;
            opacity: 0.6;
            margin-left: 4px;
        }
        .parent-link a {
            color: inherit;
            text-decoration: none;
        }
        .comments-footer {
            display: flex;
            justify-content: center;
            margin-top: 2em;
        }
        button#lmcomments {
            border: none;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            font-size: 14px;
            font-weight: 600;
            padding: 12px 32px;
            border-radius: 24px;
            background: #3182ce;
            color: #ffffff;
            cursor: pointer;
            box-shadow: 0 4px 12px rgba(49, 130, 206, 0.3);
            transition: background 0.2s, transform 0.1s;
        }
        button#lmcomments:hover {
            background: #2b6cb0;
        }
        button#lmcomments:active {
            transform: scale(0.95);
        }
        .d-none {
            display: none !important;
        }
        </style>
        </head>
        <body>
        <div id="lnw-comments-section" class="skiptranslate">
            <div class="comment-wrapper">
                <ul>
                    \(comments)
                </ul>
            </div>
            <div class="comments-footer">
                <button id="lmcomments" class="button \(hasMoreComments ? "" : "d-none")" onclick="loadMoreComments()">Load More Comments</button>
            </div>
        </div>
        
        <script>
        window.onerror = function(message, source, lineno, colno, error) {
            var errorStr = message + " at " + source + ":" + lineno + ":" + colno;
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.jsError) {
                window.webkit.messageHandlers.jsError.postMessage(errorStr);
            }
            return false;
        };

        window.loadMoreComments = function() {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.loadMoreComments) {
                window.webkit.messageHandlers.loadMoreComments.postMessage("");
            }
        }

        window.appendComments = function(newHtml, hasMore) {
            var container = document.querySelector(".comment-wrapper > ul");
            if (container) {
                container.insertAdjacentHTML('beforeend', newHtml);
            }
            var loadMoreBtn = document.getElementById("lmcomments");
            if (loadMoreBtn) {
                if (hasMore) {
                    loadMoreBtn.classList.remove("d-none");
                } else {
                    loadMoreBtn.classList.add("d-none");
                }
            }
            window.initSpoilers();
            window.assignDefaultAvatars();
            window.replaceIconClasses();
        }

        window.initSpoilers = function() {
            var spoilers = document.querySelectorAll('.comment-text[data-spoiler="1"]');
            spoilers.forEach(function(el) {
                if (!el.classList.contains('has-spoiler-click')) {
                    el.classList.add('has-spoiler-click');
                    el.addEventListener('click', function() {
                        el.classList.add('revealed');
                        el.setAttribute('data-spoiler', '0');
                    });
                }
            });
        }

        window.assignDefaultAvatars = function() {
            var avatars = document.querySelectorAll(".user-avatar img.avatar");
            avatars.forEach(function(img) {
                var src = img.getAttribute("src");
                if (!src || src.indexOf("default") !== -1 || src.trim() === "") {
                    setDefaultAvatar(img);
                }
                // Hook error listener in case network load fails
                if (!img.classList.contains('has-avatar-error')) {
                    img.classList.add('has-avatar-error');
                    img.addEventListener("error", function() {
                        setDefaultAvatar(img);
                    });
                }
            });
        }

        function setDefaultAvatar(img) {
            var username = "";
            var parent = img.closest("li");
            if (parent) {
                var usernameEl = parent.querySelector(".username");
                if (usernameEl) username = usernameEl.innerText.trim();
            }
            var initial = username ? username.charAt(0).toUpperCase() : "?";
            
            // Create a canvas-based dynamic colored avatar
            var colors = ["#3182ce", "#e53e3e", "#319795", "#d69e2e", "#805ad5", "#dd6b20"];
            var charCode = initial.charCodeAt(0) || 0;
            var color = colors[charCode % colors.length];
            
            var canvas = document.createElement("canvas");
            canvas.width = 64;
            canvas.height = 64;
            var ctx = canvas.getContext("2d");
            
            // Draw background circle
            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(32, 32, 32, 0, 2 * Math.PI);
            ctx.fill();
            
            // Draw initial text
            ctx.fillStyle = "#ffffff";
            ctx.font = "bold 32px sans-serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(initial, 32, 32);
            
            img.src = canvas.toDataURL();
            img.style.borderRadius = "50%";
        }

        window.replaceIconClasses = function() {
            var mappings = {
                "icon-thumbs-up": "fa-solid fa-thumbs-up",
                "icon-thumbs-down": "fa-solid fa-thumbs-down",
                "icon-commenting-o": "fa-regular fa-comment-dots",
                "icon-eye": "fa-solid fa-eye",
                "icon-forward": "fa-solid fa-share",
                "icon-attention": "fa-solid fa-circle-exclamation"
            };
            for (var key in mappings) {
                var els = document.querySelectorAll("." + key);
                els.forEach(function(el) {
                    el.className = mappings[key];
                });
            }
        }

        // Hook up like, dislike, and show_replies handlers
        document.addEventListener("click", function(e) {
            var showRepliesBtn = e.target.closest(".show_replies");
            if (showRepliesBtn) {
                e.preventDefault();
                var replyContainer = showRepliesBtn.closest(".reply-comments");
                if (replyContainer) {
                    var isExpanded = replyContainer.classList.toggle("expanded");
                    var link = showRepliesBtn.querySelector("a") || showRepliesBtn;
                    if (isExpanded) {
                        link.innerHTML = '<i class="fa-solid fa-eye-slash"></i> Hide Replies';
                    } else {
                        link.innerHTML = '<i class="fa-solid fa-eye"></i> Show Replies';
                    }
                }
                return;
            }

            var likeBtn = e.target.closest(".like-button");
            if (likeBtn) {
                var commentId = likeBtn.getAttribute("data-comment-id");
                if (commentId && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.likeComment) {
                    window.webkit.messageHandlers.likeComment.postMessage(commentId);
                }
                return;
            }
            
            var dislikeBtn = e.target.closest(".dislike-button");
            if (dislikeBtn) {
                var commentId = dislikeBtn.getAttribute("data-comment-id");
                if (commentId && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dislikeComment) {
                    window.webkit.messageHandlers.dislikeComment.postMessage(commentId);
                }
                return;
            }
        });

        window.updateCommentLikes = function(commentId, likes, dislikes, isLikeAction) {
            var commentEl = document.getElementById("lnw-comment-" + commentId);
            if (!commentEl) return;
            
            var likeBtn = commentEl.querySelector(".like-button");
            var dislikeBtn = commentEl.querySelector(".dislike-button");
            
            if (likeBtn) {
                var countSpan = likeBtn.querySelector("span");
                if (countSpan) countSpan.innerText = likes;
                if (isLikeAction) {
                    likeBtn.classList.toggle("checked");
                    if (dislikeBtn) dislikeBtn.classList.remove("checked");
                }
            }
            if (dislikeBtn) {
                var countSpan = dislikeBtn.querySelector("span");
                if (countSpan) countSpan.innerText = dislikes;
                if (!isLikeAction) {
                    dislikeBtn.classList.toggle("checked");
                    if (likeBtn) likeBtn.classList.remove("checked");
                }
            }
        }

        // Trigger initial spoiler and avatar checks
        window.addEventListener("DOMContentLoaded", function() {
            window.initSpoilers();
            window.assignDefaultAvatars();
            window.replaceIconClasses();
        });
        window.initSpoilers();
        window.assignDefaultAvatars();
        window.replaceIconClasses();
        </script>
        </body>
        </html>
        """
    }

    /// JSON-encode a string as a JS string literal (handles quotes/newlines/emoji).
    private static func jsString(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\""
    }
}

@MainActor
final class CommentsWebViewBridge: ObservableObject {
    weak var webView: WKWebView?
    @Published var isReady = false
}

struct CommentsWebViewWrapper: CommentsPlatformRepresentable {
    let html: String
    let bridge: CommentsWebViewBridge
    let onLoadMore: () -> Void
    let onLike: (String) -> Void
    let onDislike: (String) -> Void
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CommentsWebViewWrapper
        
        init(parent: CommentsWebViewWrapper) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "loadMoreComments" {
                DispatchQueue.main.async {
                    self.parent.onLoadMore()
                }
            } else if message.name == "likeComment", let commentId = message.body as? String {
                DispatchQueue.main.async {
                    self.parent.onLike(commentId)
                }
            } else if message.name == "dislikeComment", let commentId = message.body as? String {
                DispatchQueue.main.async {
                    self.parent.onDislike(commentId)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView {
        let webView = createWebView(context: context)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Fast-path byte-count check before the O(n) string compare —
        // body re-evaluates often (sheet toggles, theme changes) and the
        // comments HTML can be 100KB+.
        let prev = context.coordinator.parent.html
        if prev.utf8.count != html.utf8.count || prev != html {
            context.coordinator.parent = self
            uiView.loadHTMLString(html, baseURL: nil)
        }
    }
    #else
    func makeNSView(context: Context) -> WKWebView {
        let webView = createWebView(context: context)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let prev = context.coordinator.parent.html
        if prev.utf8.count != html.utf8.count || prev != html {
            context.coordinator.parent = self
            nsView.loadHTMLString(html, baseURL: nil)
        }
    }
    #endif
    
    private func createWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        let helper = ScriptMessageHandlerHelper(delegate: context.coordinator)
        userContentController.add(helper, name: "loadMoreComments")
        userContentController.add(helper, name: "likeComment")
        userContentController.add(helper, name: "dislikeComment")
        config.userContentController = userContentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif
        
        bridge.webView = webView
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }
}
