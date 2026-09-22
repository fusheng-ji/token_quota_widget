import Foundation

/// At most one collector runs in the app; a full refresh supersedes queued activity polls.
struct RefreshSchedule: Equatable, Sendable {
    enum Mode: Sendable { case all, codex }
    enum State: Equatable, Sendable {
        case idle
        case running(Mode)
        case fullQueued(Mode)
    }

    private(set) var state: State = .idle

    var showsFullRefresh: Bool {
        switch state {
        case .idle, .running(.codex): false
        case .running(.all), .fullQueued: true
        }
    }

    mutating func request(_ mode: Mode) -> Mode? {
        switch state {
        case .idle:
            state = .running(mode)
            return mode
        case let .running(active):
            if mode == .all { state = .fullQueued(active) }
            return nil
        case .fullQueued:
            return nil
        }
    }

    mutating func finish() -> Mode? {
        if case .fullQueued = state {
            state = .running(.all)
            return .all
        }
        state = .idle
        return nil
    }
}
