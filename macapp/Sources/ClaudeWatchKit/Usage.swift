import Foundation

/// Severity band for a usage percentage, driving color.
public enum UsageTier: Sendable, Equatable {
    case normal, warning, critical
}

public func usageTier(_ pct: Int) -> UsageTier {
    if pct >= 90 { return .critical }
    if pct >= 70 { return .warning }
    return .normal
}

/// Human countdown to a reset, from a unix timestamp. e.g. "resets in 2h 40m".
public func resetCountdown(resetsAt: Double, now: Double) -> String {
    let secs = max(0, resetsAt - now)
    if secs < 60 { return "resets now" }
    let mins = Int(secs / 60)
    if mins < 60 { return "resets in \(mins)m" }
    let hours = mins / 60
    if hours < 24 {
        let rem = mins % 60
        return rem > 0 ? "resets in \(hours)h \(rem)m" : "resets in \(hours)h"
    }
    return "resets in \(hours / 24)d"
}

/// Compact token count: 950, 340k, 1.2M.
public func compactTokens(_ n: Int) -> String {
    if n < 1000 { return "\(n)" }
    if n < 1_000_000 { return "\(n / 1000)k" }
    let m = Double(n) / 1_000_000
    return String(format: "%.1fM", m)
}

/// "~25m to limit" / "~1h 10m to limit" — the burn-rate projection.
public func etaToLimit(_ seconds: Double) -> String {
    let mins = max(1, Int(seconds / 60))
    if mins < 60 { return "~\(mins)m to limit" }
    let h = mins / 60, m = mins % 60
    return m > 0 ? "~\(h)h \(m)m to limit" : "~\(h)h to limit"
}
