// StatisticsView.swift
// Library and reading activity metrics using muted pastel color schemes and systemGray6 containers.

import Charts
import SwiftData
import SwiftUI

// MARK: - Muted Pastel Palette
private enum Pastel {
    static let blue = Color(red: 0.62, green: 0.76, blue: 0.88)     // Soft Sky Blue
    static let purple = Color(red: 0.74, green: 0.68, blue: 0.82)   // Soft Lavender
    static let green = Color(red: 0.66, green: 0.82, blue: 0.74)    // Soft Mint Green
    static let orange = Color(red: 0.90, green: 0.76, blue: 0.66)   // Soft Peach/Apricot
    static let teal = Color(red: 0.62, green: 0.78, blue: 0.78)     // Soft Sage/Teal
}

struct StatisticsView: View {
    @Environment(PluginManager.self) private var pluginManager
    @Query(filter: #Predicate<Novel> { $0.inLibrary }) private var libraryNovels: [Novel]
    @Query private var chapters: [Chapter]
    @Query private var categories: [Category]
    @Query(sort: \ReadingHistory.lastReadAt, order: .reverse) private var historyEntries: [ReadingHistory]

    // Summary calculations
    private var unreadCount: Int {
        chapters.filter(\.unread).count
    }

    private var downloadedCount: Int {
        chapters.filter(\.isDownloaded).count
    }

    private var lastReadText: String {
        historyEntries.first?.lastReadAt.timeAgo ?? "Never"
    }

    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary Overview Grid (systemGray6 cards, flat pastel icons)
                LazyVGrid(columns: columns, spacing: 16) {
                    summaryCard(title: "Library Novels", value: "\(libraryNovels.count)", icon: "books.vertical.fill", color: Pastel.blue)
                    summaryCard(title: "Total Chapters", value: "\(chapters.count)", icon: "list.number", color: Pastel.purple)
                    summaryCard(title: "Downloaded", value: "\(downloadedCount)", icon: "arrow.down.circle.fill", color: Pastel.green)
                    summaryCard(title: "Last Read", value: lastReadText, icon: "clock.arrow.circlepath", color: Pastel.orange)
                }

                // 1. Weekly Reading Activity Card (muted pastel purple)
                weeklyActivityCard

                // 2. Reading Progress Stacked Card (muted pastel green and purple)
                readingProgressCard

                // 3. Category Breakdown Card (muted pastel orange progress bars)
                categoryBreakdownCard

                // 4. Best Reading Hours Card (muted pastel blue bar chart)
                bestReadingHoursCard

                // 5. Novels by Source Card (muted pastel teal progress rows)
                novelsBySourceCard
            }
            .padding()
        }
        .navigationTitle("Statistics")
    }

    // MARK: - Card Container

    private struct CardContainer<Content: View>: View {
        let content: Content
        
        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }
        
        var body: some View {
            content
                .padding()
                .background(Color(UIColor.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
    }

    // MARK: - Summary Card Helper

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)

                Text(value)
                    .font(Typography.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)

                Text(title)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Data Models

    private struct DayActivity: Identifiable {
        let id = UUID()
        let date: Date
        let dayLabel: String
        let count: Int
    }

    private struct CategoryCount: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
    }

    private struct HourActivity: Identifiable {
        let id = UUID()
        let hour: Int
        let hourLabel: String
        let count: Int
    }

    private struct SourceCount: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
    }

    // MARK: - 1. Weekly Reading Activity

    private var weeklyActivityData: [DayActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var dayCounts: [Date: Int] = [:]
        for entry in historyEntries {
            let dayStart = calendar.startOfDay(for: entry.lastReadAt)
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

    private var weeklyActivityCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(Pastel.purple)
                    Text("Weekly Activity")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                
                Text("Chapters read per day in the last 7 days")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                
                let activity = weeklyActivityData
                if activity.map(\.count).reduce(0, +) > 0 {
                    Chart(activity) { day in
                        BarMark(
                            x: .value("Day", day.dayLabel),
                            y: .value("Chapters", day.count)
                        )
                        .foregroundStyle(Pastel.purple)
                        .cornerRadius(4)
                    }
                    .frame(height: 120)
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.gray.opacity(0.2))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }
                    }
                } else {
                    noDataView(message: "No reading activity recorded recently")
                }
            }
        }
    }

    // MARK: - 2. Reading Progress (Stacked Bar)

    private var totalChaptersCount: Int {
        max(chapters.count, 0)
    }

    private var readChaptersCount: Int {
        max(totalChaptersCount - unreadCount, 0)
    }

    private var readingProgressCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "percent")
                        .foregroundStyle(Pastel.green)
                    Text("Reading Progress")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                
                Text("Split of read vs unread chapters across library")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                
                if totalChaptersCount > 0 {
                    VStack(spacing: 12) {
                        Chart {
                            BarMark(
                                x: .value("Chapters", readChaptersCount)
                            )
                            .foregroundStyle(Pastel.green)
                            .cornerRadius(4)
                            
                            BarMark(
                                x: .value("Chapters", unreadCount),
                                stacking: .standard
                            )
                            .foregroundStyle(Pastel.purple)
                            .cornerRadius(4)
                        }
                        .frame(height: 28)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        
                        HStack(spacing: 20) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Pastel.green)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Read")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(readChaptersCount) (\(Int(Double(readChaptersCount) / Double(totalChaptersCount) * 100))%)")
                                        .font(Typography.caption)
                                        .bold()
                                        .foregroundStyle(.primary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Pastel.purple)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unread")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("\(unreadCount) (\(Int(Double(unreadCount) / Double(totalChaptersCount) * 100))%)")
                                        .font(Typography.caption)
                                        .bold()
                                        .foregroundStyle(.primary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    noDataView(message: "No chapters loaded in library")
                }
            }
        }
    }

    // MARK: - 3. Category Breakdown

    private var categoryData: [CategoryCount] {
        categories.map { category in
            CategoryCount(name: category.name, count: category.novels.count)
        }
        .sorted { $0.count > $1.count }
        .prefix(5)
        .map { $0 }
    }

    private var maxCategoryNovelCount: Int {
        categoryData.map(\.count).max() ?? 1
    }

    private var categoryBreakdownCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2.fill")
                        .foregroundStyle(Pastel.orange)
                    Text("Category Breakdown")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                
                Text("Distribution of novels across categories (top 5)")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                
                let categoriesList = categoryData
                if !categoriesList.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(categoriesList) { item in
                            HStack(spacing: 12) {
                                Text(item.name)
                                    .font(Typography.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .leading)
                                    .lineLimit(1)
                                
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.15))
                                            .frame(height: 10)
                                        
                                        let maxVal = maxCategoryNovelCount
                                        let progress = maxVal > 0 ? CGFloat(item.count) / CGFloat(maxVal) : 0
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Pastel.orange)
                                            .frame(width: geometry.size.width * progress, height: 10)
                                    }
                                }
                                .frame(height: 10)
                                
                                Text("\(item.count)")
                                    .font(Typography.caption)
                                    .bold()
                                    .foregroundStyle(Pastel.orange)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                } else {
                    noDataView(message: "No categories defined")
                }
            }
        }
    }

    // MARK: - 4. Best Reading Hours

    private var hourlyActivityData: [HourActivity] {
        var hourCounts: [Int: Int] = [:]
        for entry in historyEntries {
            let hour = Calendar.current.component(.hour, from: entry.lastReadAt)
            hourCounts[hour, default: 0] += 1
        }
        
        return (0..<24).map { hour in
            let label: String
            if hour == 0 {
                label = "12am"
            } else if hour < 12 {
                label = "\(hour)am"
            } else if hour == 12 {
                label = "12pm"
            } else {
                label = "\(hour - 12)pm"
            }
            return HourActivity(hour: hour, hourLabel: label, count: hourCounts[hour] ?? 0)
        }
    }

    private var peakReadingHour: String {
        let data = hourlyActivityData
        if let peak = data.max(by: { $0.count < $1.count }), peak.count > 0 {
            return peak.hourLabel
        }
        return "None"
    }

    private var bestReadingHoursCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(Pastel.blue)
                    Text("Reading Hours")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(peakReadingHour)
                        .font(.title2)
                        .bold()
                        .foregroundStyle(Pastel.blue)
                    Text("peak reading time")
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
                
                let hourlyData = hourlyActivityData
                if hourlyData.map(\.count).reduce(0, +) > 0 {
                    Chart(hourlyData, id: \.hour) { data in
                        BarMark(
                            x: .value("Hour", data.hour),
                            y: .value("Count", data.count)
                        )
                        .foregroundStyle(
                            data.hourLabel == peakReadingHour ? Pastel.blue : Pastel.blue.opacity(0.4)
                        )
                        .cornerRadius(2)
                    }
                    .frame(height: 80)
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18]) { value in
                            AxisValueLabel {
                                if let hour = value.as(Int.self) {
                                    let label = hour == 0 ? "12am" : (hour < 12 ? "\(hour)am" : (hour == 12 ? "12pm" : "\(hour-12)pm"))
                                    Text(label)
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartYAxis(.hidden)
                } else {
                    noDataView(message: "No hourly reading data available")
                }
            }
        }
    }

    // MARK: - 5. Novels by Source

    private func pluginName(for id: String) -> String {
        pluginManager.installedPlugins[id]?.name ?? id.capitalized
    }

    private var sourceCountData: [SourceCount] {
        var counts: [String: Int] = [:]
        for novel in libraryNovels {
            counts[novel.pluginId, default: 0] += 1
        }
        return counts.map { (pluginId, count) in
            SourceCount(name: pluginName(for: pluginId), count: count)
        }
        .sorted { $0.count > $1.count }
        .prefix(5)
        .map { $0 }
    }

    private var maxSourceNovelCount: Int {
        sourceCountData.map(\.count).max() ?? 1
    }

    private var novelsBySourceCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(Pastel.teal)
                    Text("Novels by Source")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                
                Text("Distribution of library novels by source plugin")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                
                let sourceList = sourceCountData
                if !sourceList.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(sourceList) { item in
                            HStack(spacing: 12) {
                                Text(item.name)
                                    .font(Typography.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                    .lineLimit(1)
                                
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.gray.opacity(0.15))
                                            .frame(height: 10)
                                        
                                        let maxVal = maxSourceNovelCount
                                        let progress = maxVal > 0 ? CGFloat(item.count) / CGFloat(maxVal) : 0
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Pastel.teal)
                                            .frame(width: geometry.size.width * progress, height: 10)
                                    }
                                }
                                .frame(height: 10)
                                
                                Text("\(item.count)")
                                    .font(Typography.caption)
                                    .bold()
                                    .foregroundStyle(Pastel.teal)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                } else {
                    noDataView(message: "No novels added to library")
                }
            }
        }
    }

    // MARK: - No Data View Helper

    private func noDataView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(message)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }
}
