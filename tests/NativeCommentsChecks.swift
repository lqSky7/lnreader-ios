import Foundation

@main struct NativeCommentsChecks {
    static func main() throws {
        let html = """
        <li id="lnw-comment-12"><div class="comment-item"><a class="username">Alice</a><time>2 hours ago</time>
        <div class="comment-text">A <strong>good</strong> chapter &amp; a quiet ending. 🙂<script>bad()</script></div>
        <button class="like-button" data-comment-id="12">1.2k</button><button class="dislike-button">3</button></div>
        <ul class="reply-comments"><li id="lnw-comment-13"><a class="username">Bob</a><div class="comment-text"><span class="spoiler">A reply, not the parent text.</span></div><button class="like-button">5</button></li></ul></li>
        <li id="lnw-comment-14"><a class="username">Carla</a><div class="comment-text">Another thought.</div><button class="like-button">7</button></li>
        """
        let comments = try NovelFireCommentsService.nativeComments(from: html)
        precondition(comments.count == 2)
        precondition(comments[0].id == "12" && comments[0].author == "Alice")
        precondition(comments[0].text == "A good chapter & a quiet ending. 🙂")
        precondition(comments[0].likes == 1200 && comments[0].dislikes == 3)
        precondition(comments[0].replies.count == 1 && comments[0].replies[0].parentID == "12")
        precondition(comments[0].replies[0].isSpoiler && !comments[0].isSpoiler)
        precondition(comments[1].replies.isEmpty && comments[1].likes == 7)
        let empty = try NovelFireCommentsService.nativeComments(from: "")
        precondition(empty.isEmpty)
        do {
            _ = try NovelFireCommentsService.nativeComments(from: "<div class='comment-text'>Unexpected format</div>")
            fatalError("Unsupported comment markup must be reported")
        } catch { precondition((error as NSError).domain == "NativeComments") }
        precondition(!NovelFireCommentsService.isAuthenticatedPage("<a href='/auth/redirect/google'>Sign in</a>"))
        precondition(!NovelFireCommentsService.isAuthenticatedPage("<script>var x = '<form id=logout-form>';</script>"))
        precondition(NovelFireCommentsService.isAuthenticatedPage("<form id='logout-form' action='/logout' method='POST'></form>"))
        for site in CommentSite.allCases {
            precondition(site.matches(host: site.domain) && site.matches(host: "www." + site.domain))
            precondition(!site.matches(host: site.domain + ".evil.invalid"))
            precondition(!site.matches(host: "not" + site.domain))
            precondition(!site.matches(host: nil))
        }
        print("PASS: native comment parsing, nested replies, counts, spoilers, HTML data isolation, guest/authenticated page detection and domain boundaries")
    }
}
