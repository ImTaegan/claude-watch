import SwiftUI
import ClaudeWatchKit

/// The account-level quota gauges (5-hour session window + weekly), shown at the
/// top of the panel. Each is a labelled bar with % used and a reset countdown.
struct UsageSummaryView: View {
    let limits: Limits
    let now: Double

    var body: some View {
        VStack(spacing: 8) {
            if let f = limits.fiveHour { gauge("Session", f) }
            if let w = limits.sevenDay { gauge("Week", w) }
        }
    }

    @ViewBuilder
    private func gauge(_ label: String, _ window: LimitWindow) -> some View {
        let tier = usageTier(window.usedPercentage)
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(label).font(.caption.weight(.semibold))
                Text(resetCountdown(resetsAt: window.resetsAt, now: now))
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text("\(window.usedPercentage)%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tier == .normal ? .primary : tier.color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(tier.barColor)
                        .frame(width: max(3, geo.size.width * CGFloat(window.usedPercentage) / 100))
                }
            }
            .frame(height: 5)
        }
    }
}
