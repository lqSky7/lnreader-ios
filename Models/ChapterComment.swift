import Foundation

/// A single user comment from a source chapter page
struct ChapterComment: Identifiable, Sendable, Hashable {
    /// Unique identifier for the comment
    let id: String
    
    /// Display name of the user who commented
    let username: String
    
    /// User profile avatar URL, if available
    let avatarURL: String?
    
    /// User's tier/role badge (e.g. "Reader", "Supporter")
    let userTier: String
    
    /// Relative time when the comment was posted (e.g. "2d", "1h")
    let postDate: String
    
    /// The comment's body HTML/text content
    let text: String
    
    /// Number of likes/upvotes
    let likes: Int
    
    /// Number of dislikes/downvotes
    let dislikes: Int
    
    /// Whether the current user liked this comment (based on website state)
    let isLiked: Bool
    
    /// Whether the current user disliked this comment (based on website state)
    let isDisliked: Bool
    
    /// Whether the comment contains spoilers and should be masked
    let isSpoiler: Bool
    
    /// List of replies nested under this comment
    let replies: [ChapterComment]
}
