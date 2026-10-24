// StatisticsView.swift
// Library and reading activity metrics in a native grouped list, charted with Swift Charts and Gauge.

import Charts
import SwiftData
import SwiftUI

// MARK: - Snapshot and chart value types

/// Everything the statistics screen shows, counted in one background pass.
private struct StatisticsSnapshot: Sendable {
    var libraryCount = 0
    var totalChapters = 0
    var unreadChapters = 0
    var downloadedChapters = 0
    var lastRead: Date?
    /// One entry per history row, reduced to the only thing the charts need.
    var historyDates: [Date] = []
    var categoryCounts: [CategoryCount] = []
    /// Grouped by source *key*; resolved to a display name on the main actor.
    var sourceCounts: [SourceCount] = []
}

private struct DayActivity: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let dayLabel: String
    let count: Int
}

private struct CategoryCount: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let count: Int
}

private struct HourActivity: Identifiable, Sendable {
    let id = UUID()
    let hour: Int
    let hourLabel: String
    let count: Int
}

private struct SourceCount: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let count: Int
}

struct StatisticsView: View {
    @Environment(SourceManager.self) private var sourceManager
    @Environment(\.modelContext) private var modelContext

    /// Everything the screen needs, counted once off the main thread.
    ///
    /// This used to be `@Query private var chapters: [Chapter]`, which pulls
    /// every chapter in the store into memory and re-runs on any write; the
    /// "downloaded" tile then faulted each chapter's `downloadItem`. On a real
    /// library that is tens of thousands of objects to render five numbers.
    @State private var stats = StatisticsSnapshot()

    // Summary calculations
    private var unreadCount: Int { stats.unreadChapters }

    private var downloadedCount: Int { stats.downloadedChapters }

    private var lastReadText: String {
        stats.lastRead?.timeAgo ?? "Never"
    }

    var body: some View {
        List {
            overviewSection
            weeklyActivitySection
            readingProgressSection
            categorySection
            readingHoursSection
            sourceSection
        }
        .settingsScreen("Statistics")
        .task { await loadStatistics() }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        Section("Overview") {
            LabeledContent {
                Text("\(stats.libraryCount)")
            } label: {
                Label("Library", systemImage: "books.vertical")
            }
            LabeledContent {
                Text("\(stats.totalChapters)")
            } label: {
                Label("Total chapters", systemImage: "list.number")
            }
            LabeledContent {
                Text("\(downloadedCount)")
            } label: {
                Label("Downloaded", systemImage: "arrow.down.circle")
            }
            LabeledContent {
                Text(lastReadText)
            } label: {
                Label("Last read", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    // MARK: - Snapshot

    private func loadStatistics() async {
        let container = modelContext.container
        let snapshot = await Task.detached(priority: .userInitiated) { () -> StatisticsSnapshot in
            let context = ModelContext(container)
            var snapshot = StatisticsSnapshot()

            snapshot.libraryCount =
                (try? context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.inLibrary }))) ?? 0
            snapshot.totalChapters =
                (try? context.fetchCount(FetchDescriptor<Chapter>())) ?? 0
            snapshot.unreadChapters =
                (try? context.fetchCount(FetchDescriptor<Chapter>(predicate: #Predicate { $0.read == false }))) ?? 0
            // Download rows are few (one per downloaded chapter), and a
            // predicate cannot compare an enum case, so count them here.
            let downloads = (try? context.fetch(FetchDescriptor<DownloadItem>())) ?? []
            snapshot.downloadedChapters = downloads.count { $0.state == DownloadState.completed }

            // History rows are needed as dates, not objects, so map them here
            // and let the model objects go.
            let historyDescriptor = FetchDescriptor<History>(
                sortBy: [SortDescriptor(\.lastRead, order: .reverse)]
            )
            let history = (try? context.fetch(historyDescriptor)) ?? []
            snapshot.historyDates = history.map(\.lastRead)
            snapshot.lastRead = history.first?.lastRead

            let entries = (try? context.fetch(
                FetchDescriptor<Entry>(predicate: #Predicate { $0.inLibrary })
            )) ?? []
            var bySource: [String: Int] = [:]
            for entry in entries { bySource[entry.sourceKey, default: 0] += 1 }
            snapshot.sourceCounts = bySource
                .map { SourceCount(name: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }

            let categories = (try? context.fetch(
                FetchDescriptor<Category>(sortBy: [SortDescriptor(\.order)])
            )) ?? []
            snapshot.categoryCounts = categories
                .map { CategoryCount(name: $0.name, count: $0.entries.count) }
                .sorted { $0.count > $1.count }

            return snapshot
        }.value

        stats = snapshot
    }

    // MARK: - Weekly activity

    private var weeklyActivityData: [DayActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var dayCounts: [Date: Int] = [:]
        for date in stats.historyDates {
            let dayStart = calendar.startOfDay(for: date)
            dayCounts[dayStart, default: 0] += 1
        }

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "E"

        var data: [DayActivity] = []
        for offset in (0..<7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -offset, to: today) {
                let label = dayFormatter.string(from: date)
                let count = dayCounts[date] ?? 0
                data.append(DayActivity(date: date, dayLabel: label, count: count))
            }
        }
        return data
    }

    private var weeklyActivitySection: some View {
        Section {
            let activity = weeklyActivityData
            if activity.map(\.count).reduce(0, +) > 0 {
                Chart(activity) { day in
                    BarMark(
                        x: .value("Day", day.dayLabel),
                        y: .value("Chapters", day.count)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .cornerRadius(4)
                }
                .frame(height: 120)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3))
                }
                .padding(.vertical, 4)
            } else {
                noData("No reading activity recorded recently")
            }
        } header: {
            Text("Weekly activity")
        } footer: {
            Text("Chapters read per day in the last 7 days.")
        }
    }

    // MARK: - Reading progress

    private var totalChaptersCount: Int {
        max(stats.totalChapters, 0)
    }

    private var readChaptersCount: Int {
        max(totalChaptersCount - unreadCount, 0)
    }

    private var readingProgressSection: some View {
        Section {
            if totalChaptersCount > 0 {
                Gauge(value: Double(readChaptersCount), in: 0...Double(totalChaptersCount)) {
                    Text("Read")
                }
                .gaugeStyle(.linearCapacity)
                .tint(AppTheme.accent)
                .padding(.vertical, 4)

                LabeledContent("Read", value: "\(readChaptersCount) (\(percent(readChaptersCount))%)")
                LabeledContent("Unread", value: "\(unreadCount) (\(percent(unreadCount))%)")
            } else {
                noData("No chapters loaded in library")
            }
        } header: {
            Text("Reading progress")
        } footer: {
            Text("Read versus unread chapters across the library.")
        }
    }

    private func percent(_ count: Int) -> Int {
        guard totalChaptersCount > 0 else { return 0 }
        return Int(Double(count) / Double(totalChaptersCount) * 100)
    }

    // MARK: - Category breakdown

    private var categoryData: [CategoryCount] {
        Array(stats.categoryCounts.prefix(5))
    }

    private var categorySection: some View {
        Section {
            if categoryData.isEmpty {
                noData("No categories defined")
            } else {
                rankedChart(categoryData.map { RankedCount(name: $0.name, count: $0.count) })
            }
        } header: {
            Text("Category breakdown")
        } footer: {
            Text("Library entries across categories (top 5).")
        }
    }

    // MARK: - Reading hours

    private var hourlyActivityData: [HourActivity] {
        var hourCounts: [Int: Int] = [:]
        let calendar = Calendar.current
        for date in stats.historyDates {
            hourCounts[calendar.component(.hour, from: date), default: 0] += 1
        }
        return (0..<24).map { hour in
            HourActivity(hour: hour, hourLabel: Self.hourLabel(hour), count: hourCounts[hour] ?? 0)
        }
    }

    private static func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12am" }
        if hour < 12 { return "\(hour)am" }
        if hour == 12 { return "12pm" }
        return "\(hour - 12)pm"
    }

    private var peakReadingHour: String {
        if let peak = hourlyActivityData.max(by: { $0.count < $1.count }), peak.count > 0 {
            return peak.hourLabel
        }
        return "None"
    }

    private var readingHoursSection: some View {
        Section("Reading hours") {
            LabeledContent("Peak reading time", value: peakReadingHour)

            let hourlyData = hourlyActivityData
            if hourlyData.map(\.count).reduce(0, +) > 0 {
                Chart(hourlyData, id: \.hour) { data in
                    BarMark(
                        x: .value("Hour", data.hour),
                        y: .value("Count", data.count)
                    )
                    .foregroundStyle(data.hourLabel == peakReadingHour ? AnyShapeStyle(AppTheme.accent) : AnyShapeStyle(.secondary))
                    .cornerRadius(2)
                }
                .frame(height: 100)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text(Self.hourLabel(hour))
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .padding(.vertical, 4)
            } else {
                noData("No hourly reading data available")
            }
        }
    }

    // MARK: - Books by source

    private func sourceName(for key: String) -> String {
        sourceManager.source(forKey: key)?.name ?? SourceKey.identifier(from: key)
    }

    private var sourceCountData: [RankedCount] {
        stats.sourceCounts
            .prefix(5)
            .map { RankedCount(name: sourceName(for: $0.name), count: $0.count) }
    }

    private var sourceSection: some View {
        Section {
            let list = sourceCountData
            if list.isEmpty {
                noData("No novels added to library")
            } else {
                rankedChart(list)
            }
        } header: {
            Text("Books by source")
        } footer: {
            Text("Library entries by source.")
        }
    }

    // MARK: - Helpers

    /// Horizontal bars with the count at the end of each, largest first.
    private func rankedChart(_ items: [RankedCount]) -> some View {
        Chart(items) { item in
            BarMark(
                x: .value("Titles", item.count),
                y: .value("Name", item.name)
            )
            .foregroundStyle(AppTheme.accent)
            .cornerRadius(4)
            .annotation(position: .trailing) {
                Text("\(item.count)")
                    .font(Typography.small)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis(.hidden)
        .frame(height: CGFloat(items.count) * 36 + 8)
        .padding(.vertical, 4)
    }

    private func noData(_ message: String) -> some View {
        Label(message, systemImage: "chart.pie")
            .font(Typography.caption)
            .foregroundStyle(.secondary)
    }
}

private struct RankedCount: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
}
