import Foundation

/// A mock source plugin with hardcoded sample data for UI development and testing.
struct MockSource: SourcePlugin {
    let id = "mock-source"
    let name = "Mock Source"
    let iconURL = "https://picsum.photos/64/64?random=0"
    let siteURL = "https://example.com"
    let language = "English"
    let version = "1.0.0"

    // MARK: - Sample Data

    private static let sampleNovels: [PartialNovel] = (1...10).map { i in
        PartialNovel(
            name: MockSource.novelNames[i - 1],
            path: "/novel/\(i)",
            cover: "https://picsum.photos/300/420?random=\(i)"
        )
    }

    private static let novelNames = [
        "The Beginning After The End",
        "Solo Leveling: Ragnarok",
        "Omniscient Reader's Viewpoint",
        "Mushoku Tensei: Jobless Reincarnation",
        "Classroom of the Elite",
        "Overlord",
        "That Time I Got Reincarnated as a Slime",
        "The Rising of the Shield Hero",
        "Re:Zero − Starting Life in Another World",
        "Sword Art Online: Progressive",
    ]

    private static let sampleGenres = [
        "Action, Adventure, Fantasy",
        "Action, Fantasy, Martial Arts",
        "Action, Adventure, Fantasy, Mystery",
        "Adventure, Drama, Fantasy, Romance",
        "Drama, Psychological, School Life",
        "Action, Adventure, Fantasy, Supernatural",
        "Action, Adventure, Comedy, Fantasy",
        "Action, Adventure, Drama, Fantasy",
        "Adventure, Drama, Fantasy, Psychological",
        "Action, Adventure, Romance, Sci-Fi",
    ]

    private static let sampleSummaries = [
        "King Grey has unrivaled strength, wealth, and prestige in a world governed by martial ability. However, solitude lingers closely behind those with great power.",
        "After the fierce battles, peace has finally returned. But a new threat emerges from the shadows, and hunters must rise once again.",
        "Dokja was an average office worker whose sole hobby was reading a web novel called 'Three Ways to Survive the Apocalypse.' One day, the novel became reality.",
        "A 34-year-old NEET is reincarnated into a world of sword and sorcery. Armed with memories of his past life, he is determined to live this new life with no regrets.",
        "Students of the prestigious Tokyo Metropolitan Advanced Nurturing High School are given remarkable freedom—if they can find their way in this competitive academic world.",
        "The final hour of the popular virtual reality game Yggdrasil has come. However, Momonga decides to not log out.",
        "Satoru Mikami is a typical corporate worker, until he is stabbed by a random assailant and reincarnated as a slime in a fantasy world.",
        "Iwatani Naofumi was summoned into a parallel world along with three other people to become the world's Heroes.",
        "Subaru Natsuki is transported to a fantasy world on his way home from the convenience store. The only ability he has is 'Return by Death.'",
        "In the world of Sword Art Online, Kirito and Asuna venture through Aincrad floor by floor in this retelling of the original saga.",
    ]

    // MARK: - Protocol Methods

    func popularNovels(page: Int) async throws -> [PartialNovel] {
        // Simulate network delay
        try await Task.sleep(for: .milliseconds(500))
        return Self.sampleNovels
    }

    func searchNovels(query: String, page: Int) async throws -> [PartialNovel] {
        try await Task.sleep(for: .milliseconds(300))
        let lowered = query.lowercased()
        return Self.sampleNovels.filter { $0.name.lowercased().contains(lowered) }
    }

    func parseNovel(path: String) async throws -> SourceNovel {
        try await Task.sleep(for: .milliseconds(400))

        let index = novelIndex(from: path)

        let chapters: [SourceChapter] = (1...20).map { ch in
            SourceChapter(
                name: "Chapter \(ch): \(chapterTitle(ch))",
                path: "\(path)/chapter/\(ch)",
                chapterNumber: Double(ch),
                releaseTime: "2025-01-\(String(format: "%02d", ch))"
            )
        }

        return SourceNovel(
            name: Self.novelNames[index],
            path: path,
            cover: "https://picsum.photos/300/420?random=\(index + 1)",
            genres: Self.sampleGenres[index],
            summary: Self.sampleSummaries[index],
            author: "Author \(index + 1)",
            artist: "Artist \(index + 1)",
            status: index.isMultiple(of: 2) ? "Ongoing" : "Completed",
            chapters: chapters,
            totalPages: nil
        )
    }

    func parseChapter(path: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))

        let chapterNum = path.split(separator: "/").last.flatMap { Int($0) } ?? 1

        return """
        <h2>Chapter \(chapterNum): \(chapterTitle(chapterNum))</h2>
        <p>The morning sun cast long shadows across the ancient courtyard as our protagonist \
        stepped through the weathered gates. The air carried whispers of forgotten magic, and \
        every stone seemed to pulse with stories untold.</p>
        <p>\"You shouldn't have come here,\" a voice echoed from the darkness beyond the \
        archway. The words hung in the air like mist, neither threatening nor welcoming—simply \
        a statement of fact that resonated with the weight of centuries.</p>
        <p>Despite the warning, there was no turning back. The path ahead wound through corridors \
        of crystallized starlight, each step revealing new wonders that defied the laws of the \
        mundane world left behind. <em>This was the beginning of something extraordinary.</em></p>
        <p>The ancient texts had spoken of this place—a nexus where reality folded upon itself \
        like the pages of an infinite book. Here, the boundaries between worlds grew thin, and \
        those brave or foolish enough to walk these halls could glimpse the threads that wove \
        the fabric of existence itself.</p>
        <p><strong>\"Remember,\"</strong> the elder had said before the journey began, \
        <strong>\"what you seek is not always what you find, but what finds you is always what \
        you need.\"</strong></p>
        <p>And so the chapter of discovery began, one careful step at a time, into the unknown \
        depths of a world that had waited an eternity to be explored.</p>
        """
    }

    // MARK: - Private Helpers

    private func novelIndex(from path: String) -> Int {
        let num = path.split(separator: "/").last.flatMap { Int($0) } ?? 1
        return max(0, min(num - 1, Self.novelNames.count - 1))
    }

    private func chapterTitle(_ number: Int) -> String {
        let titles = [
            "The Awakening", "First Steps", "Shadows Gathering",
            "Trial by Fire", "The Hidden Path", "Crossroads",
            "Into the Storm", "Revelations", "The Calm Before",
            "Rising Tide", "Fractured Light", "The Abyss Gazes Back",
            "A Glimmer of Hope", "Shattered Bonds", "The Long Road",
            "Convergence", "Breaking Point", "Ashes and Embers",
            "The Final Gambit", "Dawn of a New Era",
        ]
        return titles[(number - 1) % titles.count]
    }
}
