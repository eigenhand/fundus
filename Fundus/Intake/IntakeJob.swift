import SwiftUI
import UIKit

/// One shot in the queue.
///
/// This was once called `IntakeState` and there was exactly one of it: a photo held
/// the whole screen until the model had finished reading. But whoever stands in front
/// of a shelf does not take one photo, they take twelve — and then waited half a
/// minute twelve times over with nothing to do.
///
/// Now every photo is a job with its own state, and the app works several of them side
/// by side. The checking step is no longer compulsory but an offer: the job waits in
/// the queue until somebody taps it.
@Observable @MainActor
final class IntakeJob: Identifiable {

    enum Phase: Equatable {
        /// In the queue, but no worker free yet.
        case waiting
        case reading
        /// Identifiers are being looked up on the web. Its own phase, because the step
        /// takes seconds and the user would otherwise face a half-finished list.
        case looking(done: Int, total: Int)
        /// Finished reading, waiting for the human.
        case review
        /// Read, and there was no inventory in the photo.
        ///
        /// Its own phase and not `failed`, although it used to sit there. A photo of
        /// the cellar window is not an error but an answer — and a red exclamation mark
        /// for it teaches the user to overlook red exclamation marks. Then they stop
        /// seeing the real one too.
        case empty
        case failed(String)

        /// Whether this job is currently occupying a worker.
        ///
        /// `review` explicitly does not count: a finished job is waiting for the user,
        /// not for processing time, and must not hold up the next one.
        var isBusy: Bool {
            switch self {
            case .reading, .looking: return true
            case .waiting, .review, .empty, .failed: return false
            }
        }

        var isWaiting: Bool { self == .waiting }
    }

    let id = UUID()
    var phase: Phase = .waiting

    /// Already scaled down to sending size.
    ///
    /// And at queuing time, not only at the call: a queue of twelve phone photos at
    /// full resolution is several hundred megabytes in memory, for pixels that neither
    /// the model nor the evidence ever sees — both routes scale down to the same edge
    /// length anyway.
    let image: UIImage
    /// The symbol in the queue.
    let thumbnail: UIImage

    var placeID: UUID?
    var hint: String
    var result = IntakeResult()
    /// What has arrived from the model so far — only so that it is visible that
    /// something is happening. Showing the raw JSON would be worse than a spinner;
    /// what gets shown is the number of characters.
    var received = 0
    let queuedAt = Date()

    /// Not observed: the task is bookkeeping, not state for the interface.
    @ObservationIgnored var task: Task<Void, Never>?

    init(image: UIImage, placeID: UUID?, hint: String) {
        self.image = image.scaledDown(maxEdge: 1_400)
        self.thumbnail = image.scaledDown(maxEdge: 240)
        self.placeID = placeID
        self.hint = hint
    }

    var acceptedCount: Int { result.proposals.filter(\.accepted).count }

    /// What the big button in the checking step does.
    ///
    /// As a rule here and not as a question mark in the view, because something was
    /// broken about exactly this: the button read "take over nothing" and was disabled.
    /// Whoever unticked everything in order to be rid of a shot was stuck — the label
    /// promised an action, the button refused it. Ticking nothing does not mean "no
    /// action", it means "this shot should go".
    enum CommitAction: Equatable {
        case take(Int)
        case discard

        var label: String {
            switch self {
            case .take(let n): return String(localized: "\(n) übernehmen")
            case .discard:     return String(localized: "Aufnahme verwerfen")
            }
        }
    }

    var commitAction: CommitAction {
        acceptedCount == 0 ? .discard : .take(acceptedCount)
    }

    /// What stands on the symbol.
    var badge: String? {
        switch phase {
        case .review: return result.proposals.isEmpty ? "0" : "\(result.proposals.count)"
        case .empty:  return "\u{2013}"
        case .failed: return "!"
        case .waiting, .reading, .looking: return nil
        }
    }
}

/// Who goes next.
///
/// Its own type and a pure function, because this is exactly where the error you
/// cannot see would sit: too many calls at once cost money and earn a throttle, too
/// few keep the user waiting, and a job hanging in the checking step must not hold on
/// to a worker. As a function over a list of phases that is testable; as three
/// conditions in the middle of a loop it is not.
enum IntakeSchedule {

    /// How many jobs may stand in the queue at all.
    ///
    /// Not because of processing time but because of memory: every photo sits in
    /// memory, scaled down, until it is taken over or discarded.
    static let maxQueued = 24

    /// The bounds within which the concurrency can be set.
    static let concurrencyRange = 1 ... 6

    /// The places in the queue that may start now — in the order in which they were
    /// queued.
    static func startable(_ phases: [IntakeJob.Phase], concurrency: Int) -> [Int] {
        var free = concurrency.clamped(to: concurrencyRange) - phases.filter(\.isBusy).count
        guard free > 0 else { return [] }

        var out: [Int] = []
        for (index, phase) in phases.enumerated() where phase.isWaiting {
            out.append(index)
            free -= 1
            if free == 0 { break }
        }
        return out
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
