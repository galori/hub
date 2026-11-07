import Foundation

enum HotkeyHeartbeatPolicy {
    static let slowResponseThreshold: TimeInterval = 1

    static func responseLatency(sentAt: TimeInterval,
                                responseTimestamp: TimeInterval,
                                receivedAt: TimeInterval,
                                maximumRoundTrip: TimeInterval = 5,
                                maximumResponseAge: TimeInterval = 3) -> TimeInterval? {
        let roundTrip = receivedAt - sentAt
        let responseAge = receivedAt - responseTimestamp
        guard responseTimestamp >= sentAt,
              roundTrip >= 0,
              roundTrip <= maximumRoundTrip,
              responseAge >= 0,
              responseAge <= maximumResponseAge else {
            return nil
        }
        return roundTrip
    }
}

struct HotkeyRestartBudget: Codable, Equatable {
    private(set) var attempts: [TimeInterval]

    init(attempts: [TimeInterval] = []) {
        self.attempts = attempts.sorted()
    }

    func nextAllowedTime(at now: TimeInterval) -> TimeInterval? {
        let recentMinute = attempts.filter { $0 <= now && now - $0 < 60 }
        let recentTenMinutes = attempts.filter { $0 <= now && now - $0 < 600 }
        var nextAllowed = now

        if let lastAttempt = recentMinute.last {
            nextAllowed = max(nextAllowed, lastAttempt + 60)
        }
        if recentTenMinutes.count >= 3, let oldestAttempt = recentTenMinutes.first {
            nextAllowed = max(nextAllowed, oldestAttempt + 600)
        }
        return nextAllowed > now ? nextAllowed : nil
    }

    mutating func record(at timestamp: TimeInterval) {
        attempts = attempts.filter { timestamp >= $0 && timestamp - $0 < 600 }
        attempts.append(timestamp)
    }
}
