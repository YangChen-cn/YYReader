import SwiftUI

@MainActor
final class ReaderScrollState {
    private(set) var metrics = ReaderScrollMetrics.zero
    private(set) var phase = ScrollPhase.idle
    private(set) var visibleTargets: [ReaderScrollTarget] = []

    private var commandedOffsetY: Double?
    private var lastCommittedTarget: ReaderScrollTarget?
    private var visibleTargetsRevision = 0
    private var deferredCommitBaselineRevision: Int?
    private var deferredCommitDelayElapsed = false
    private var deferredCommitTask: Task<Void, Never>?
    private var scrollTransactionActive = false

    var topVisibleTarget: ReaderScrollTarget? {
        visibleTargets.first
    }

    var hasPendingDeferredCommit: Bool {
        deferredCommitBaselineRevision != nil
    }

    var canFinishDeferredCommit: Bool {
        hasPendingDeferredCommit && deferredCommitDelayElapsed && phase == .idle
    }

    func update(metrics: ReaderScrollMetrics) {
        self.metrics = metrics
    }

    func update(visibleTargets: [ReaderScrollTarget]) {
        guard self.visibleTargets != visibleTargets else { return }
        self.visibleTargets = visibleTargets
        visibleTargetsRevision += 1
    }

    func update(phase: ScrollPhase) {
        self.phase = phase
        switch phase {
        case .tracking, .interacting, .decelerating:
            commandedOffsetY = nil
        case .idle:
            commandedOffsetY = nil
        case .animating:
            break
        }
    }

    func destinationY(distance: Double) -> Double {
        let currentY = commandedOffsetY ?? metrics.contentOffsetY
        let destination = ReaderPageScroll.destinationY(
            currentY: currentY,
            viewportHeight: metrics.viewportHeight,
            contentHeight: metrics.contentHeight,
            distance: distance
        )
        commandedOffsetY = destination
        return destination
    }

    func pageDestinationY(direction: Double) -> Double {
        destinationY(distance: ReaderPageScroll.pageDistance(viewportHeight: metrics.viewportHeight) * direction)
    }

    func requestDeferredCommit() {
        deferredCommitBaselineRevision = visibleTargetsRevision
        deferredCommitDelayElapsed = false
    }

    func scheduleDeferredCommit(
        after delay: Duration,
        action: @escaping @MainActor () -> Void
    ) {
        deferredCommitTask?.cancel()
        deferredCommitTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard let self else { return }
            deferredCommitTask = nil
            markDeferredCommitDelayElapsed()
            action()
        }
    }

    func markDeferredCommitDelayElapsed() {
        deferredCommitDelayElapsed = true
    }

    func beginScrollTransactionIfNeeded() -> Bool {
        guard !scrollTransactionActive else { return false }
        scrollTransactionActive = true
        return true
    }

    func finishScrollTransactionIfNeeded() -> Bool {
        guard scrollTransactionActive else { return false }
        scrollTransactionActive = false
        return true
    }

    func releaseProgrammaticPosition() {
        commandedOffsetY = nil
    }

    func finishDeferredCommit() -> ReaderScrollTarget? {
        guard canFinishDeferredCommit,
              let baselineRevision = deferredCommitBaselineRevision else {
            return nil
        }
        deferredCommitBaselineRevision = nil
        deferredCommitDelayElapsed = false
        // A clamped or intra-paragraph key movement has no new reading position.
        guard visibleTargetsRevision > baselineRevision else { return nil }
        return consumeVisibleTargetForCommit()
    }

    func cancelDeferredCommit() {
        deferredCommitTask?.cancel()
        deferredCommitTask = nil
        deferredCommitBaselineRevision = nil
        deferredCommitDelayElapsed = false
    }

    func consumeVisibleTargetForCommit() -> ReaderScrollTarget? {
        guard phase == .idle,
              let target = topVisibleTarget,
              target != lastCommittedTarget else {
            return nil
        }
        lastCommittedTarget = target
        return target
    }
}
