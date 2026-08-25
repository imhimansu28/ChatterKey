import Charts
import SwiftUI

private enum DashboardPeriod: String, CaseIterable, Identifiable {
    case week = "7 Days"
    case month = "30 Days"
    case all = "All Time"

    var id: String { rawValue }
}

private struct DailyWordTotal: Identifiable {
    let date: Date
    let words: Int
    var id: Date { date }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var period: DashboardPeriod = .month
    var embedded = false

    @ViewBuilder var body: some View {
        if embedded {
            dashboardSections
        } else {
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    dashboardSections.padding(22)
                }
            }
            .frame(minWidth: 740, idealWidth: 820, minHeight: 560, idealHeight: 650)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var dashboardSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            if embedded {
                Picker("Period", selection: $period) {
                    ForEach(DashboardPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)
            }
            metrics
            activityCard
            lowerCards
        }
    }

    @ViewBuilder private var lowerCards: some View {
        if embedded {
            VStack(spacing: 16) {
                insightsCard
                costCard
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                insightsCard
                costCard
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("Dashboard")
                    .font(.system(size: 20, weight: .semibold))
                Text("Local usage, estimated provider cost, and speaking insights")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Period", selection: $period) {
                ForEach(DashboardPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 230)
        }
        .padding(.horizontal, 22)
        .frame(height: 78)
    }

    private var metrics: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: embedded ? 2 : 4), spacing: 12) {
            metricCard("Whole-process estimate", value: formattedCost, detail: "transcription + polish · USD", icon: "dollarsign.circle")
            metricCard("Words spoken", value: totalWords.formatted(), detail: "across dictations", icon: "text.word.spacing")
            metricCard("Dictations", value: records.count.formatted(), detail: "completed", icon: "waveform")
            metricCard("Speaking time", value: formattedDuration, detail: averageWPM, icon: "clock")
        }
    }

    private var activityCard: some View {
        dashboardCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Words by day").font(.system(size: 13, weight: .semibold))
                    Text("Your voice-writing activity over the selected period")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Stored locally")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.green.opacity(0.1), in: Capsule())
            }

            if dailyWords.allSatisfy({ $0.words == 0 }) {
                emptyChart
            } else {
                Chart(dailyWords) { item in
                    BarMark(
                        x: .value("Day", item.date, unit: .day),
                        y: .value("Words", item.words)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(dailyWords.count / 7, 1))) { _ in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 170)
            }
        }
    }

    private var insightsCard: some View {
        dashboardCard {
            Label("Speaking insights", systemImage: "lightbulb")
                .font(.system(size: 13, weight: .semibold))
            if topSuggestions.isEmpty {
                Text("Complete a few dictations to receive small suggestions about repeated phrases and clarity.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(topSuggestions.enumerated()), id: \.offset) { index, suggestion in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20, height: 20)
                            .background(Color.accentColor.opacity(0.1), in: Circle())
                        Text(suggestion)
                            .font(.system(size: 11.5))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    if index < topSuggestions.count - 1 { Divider().opacity(0.6) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var costCard: some View {
        dashboardCard {
            Label("Cost transparency", systemImage: "chart.pie")
                .font(.system(size: 13, weight: .semibold))
            ForEach(providerCosts, id: \.provider) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.provider.title).font(.system(size: 11.5, weight: .medium))
                        Text("\(item.count) request\(item.count == 1 ? "" : "s")")
                            .font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.cost, format: .currency(code: "USD").precision(.fractionLength(4)))
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                }
            }
            Divider().opacity(0.6)
            Text("The estimate includes audio transcription and, when Smart Polish is enabled, approximate input/output token cost. Provider invoices remain the final source of truth.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Edit Cost Rates") {
                    SettingsWindowController.shared.show(appState: appState, section: .provider)
                }
                .controlSize(.small)
                Spacer()
                if !appState.usageRecords.isEmpty {
                    Button("Clear Usage", role: .destructive) { appState.clearUsage() }
                        .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func metricCard(_ title: String, value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10.5, weight: .semibold))
                Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.7))
    }

    private func dashboardCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.7))
    }

    private var emptyChart: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 24)).foregroundStyle(.tertiary)
            Text("No usage recorded for this period")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
    }

    private var records: [UsageRecord] {
        let calendar = Calendar.current
        let cutoff: Date?
        switch period {
        case .week: cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date()))
        case .month: cutoff = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: Date()))
        case .all: cutoff = nil
        }
        guard let cutoff else { return appState.usageRecords }
        return appState.usageRecords.filter { $0.createdAt >= cutoff }
    }

    private var totalWords: Int { records.reduce(0) { $0 + $1.wordCount } }
    private var totalSeconds: Double { records.reduce(0) { $0 + $1.audioDurationSeconds } }
    private var totalCost: Double { records.reduce(0) { $0 + $1.estimatedCostUSD } }

    private var formattedCost: String {
        if totalCost > 0, totalCost < 0.01 { return "<$0.01" }
        return totalCost.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private var formattedDuration: String {
        if totalSeconds < 60 { return "\(Int(totalSeconds.rounded()))s" }
        return "\(Int(totalSeconds / 60))m"
    }

    private var averageWPM: String {
        guard totalSeconds >= 10 else { return "average speed" }
        return "\(Int(Double(totalWords) / totalSeconds * 60)) words/min"
    }

    private var topSuggestions: [String] {
        var counts: [String: Int] = [:]
        records.flatMap(\.suggestions).forEach { counts[$0, default: 0] += 1 }
        return counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.prefix(3).map(\.key)
    }

    private var providerCosts: [(provider: AIProvider, cost: Double, count: Int)] {
        AIProvider.allCases.compactMap { provider in
            let matches = records.filter { $0.provider == provider }
            guard !matches.isEmpty else { return nil }
            return (provider, matches.reduce(0) { $0 + $1.estimatedCostUSD }, matches.count)
        }
    }

    private var dailyWords: [DailyWordTotal] {
        let calendar = Calendar.current
        let dayCount = period == .week ? 7 : (period == .month ? 30 : min(max(daysSinceFirstRecord, 7), 90))
        let today = calendar.startOfDay(for: Date())
        return (0..<dayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let words = records.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }.reduce(0) { $0 + $1.wordCount }
            return DailyWordTotal(date: date, words: words)
        }
    }

    private var daysSinceFirstRecord: Int {
        guard let oldest = records.last?.createdAt else { return 7 }
        return (Calendar.current.dateComponents([.day], from: oldest, to: Date()).day ?? 0) + 1
    }
}
