import Foundation

/// A usage milestone worth notifying about.
public enum UsageAlert: Equatable, Sendable {
    case session(pct: Int)
    case weekly(pct: Int)
    case context(project: String, pct: Int)
}

/// Pure detector for usage threshold crossings. `fired` is opaque carry-over
/// state (keys for thresholds already announced); pass the same set back each
/// call. On the first poll (`hasBaseline` false) it only records what's already
/// crossed so we don't alert-storm at launch. Window alerts re-arm when the
/// window resets (the key embeds `resets_at`); context alerts re-arm when a
/// chat's context drops back below the threshold (e.g. after /compact).
public func detectUsageAlerts(
    _ payload: StatusPayload,
    sessionThresholds: [Int],
    weeklyThresholds: [Int],
    contextThreshold: Int,
    fired: inout Set<String>,
    hasBaseline: Bool
) -> [UsageAlert] {
    var out: [UsageAlert] = []

    func windowAlerts(_ w: LimitWindow?, _ thresholds: [Int],
                      _ tag: String, _ make: (Int) -> UsageAlert) {
        guard let w else { return }
        for t in thresholds where w.usedPercentage >= t {
            let key = "\(tag)@\(Int(w.resetsAt))@\(t)"
            if fired.insert(key).inserted, hasBaseline {
                out.append(make(t))
            }
        }
    }

    windowAlerts(payload.limits?.fiveHour, sessionThresholds, "session") { .session(pct: $0) }
    windowAlerts(payload.limits?.sevenDay, weeklyThresholds, "weekly") { .weekly(pct: $0) }

    // Drop fired keys from previous windows so the set stays bounded over a
    // long-running session (each reset embeds a new resets_at).
    func prune(_ tag: String, _ w: LimitWindow?) {
        guard let w else { return }
        let current = "\(tag)@\(Int(w.resetsAt))@"
        fired = fired.filter { !$0.hasPrefix("\(tag)@") || $0.hasPrefix(current) }
    }
    prune("session", payload.limits?.fiveHour)
    prune("weekly", payload.limits?.sevenDay)

    for a in payload.agents {
        guard let pct = a.contextPct else { continue }
        let key = "ctx@\(a.id)"
        if pct >= contextThreshold {
            if fired.insert(key).inserted, hasBaseline {
                out.append(.context(project: a.project, pct: pct))
            }
        } else {
            fired.remove(key)  // re-arm once it drops back down
        }
    }
    return out
}
