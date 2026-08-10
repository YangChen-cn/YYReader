import SwiftUI

@MainActor
final class ReaderScrollState {
    private(set) var metrics = ReaderScrollMetrics.zero
    private(set) var phase = ScrollPhase.idle
    private(set) var visibleTargets: [ReaderScrollTarget] = []

    private var commandedOffsetY: Double?
    private var lastCommittedTarget: ReaderScrollTarget?
    private var immediateCommitRequested = false

    var topVisibleTarget: ReaderScrollTarget? {
        visibleTargets.first
    }

    var hasImmediateCommitRequest: Bool {
        immediateCommitRequested && phase == .idle
    }

    func update(metrics: ReaderScrollMetrics) {
        self.metrics = metrics
    }

    func update(visibleTargets: [ReaderScrollTarget]) {
        self.visibleTargets = visibleTargets
    }

    func update(phase: ScrollPhase) {
        self.phase = phase
        switch phase {
        case .tracking, .interacting, .decelerating:
            commandedOffsetY = nil
        case .idle:
            commandedOffsetY = nil
            immediateCommitRequested = false
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

    func requestImmediateCommit() {
        immediateCommitRequested = true
    }

    func releaseProgrammaticPosition() {
        commandedOffsetY = nil
    }

    func consumeImmediateCommitTarget() -> ReaderScrollTarget? {
        guard hasImmediateCommitRequest else { return nil }
        immediateCommitRequested = false
        return consumeVisibleTargetForCommit()
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
