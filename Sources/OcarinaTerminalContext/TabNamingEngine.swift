import Foundation

/// Decides whether an observation is allowed to rename a tab.
///
/// This is the whole of the stability story from the design doc. It is a pure
/// value type on purpose: every rule below is testable without a PTY, a
/// process tree, or a clock.
public struct TabNamingEngine: Sendable {
    public struct Policy: Sendable, Equatable {
        /// Below this, an observation is ignored outright.
        public var minimumConfidence: Double
        /// A same-source rival must beat the incumbent by this much.
        public var replacementMargin: Double
        /// How long a title is protected from same-source replacement.
        public var minimumDwell: TimeInterval
        /// A higher-priority source needs at least this much to preempt.
        public var preemptionConfidence: Double

        public init(
            minimumConfidence: Double = 0.35,
            replacementMargin: Double = 0.15,
            minimumDwell: TimeInterval = 90,
            preemptionConfidence: Double = 0.5
        ) {
            self.minimumConfidence = minimumConfidence
            self.replacementMargin = replacementMargin
            self.minimumDwell = minimumDwell
            self.preemptionConfidence = preemptionConfidence
        }

        public static let `default` = Policy()
    }

    public enum Decision: Sendable, Equatable {
        case accepted
        /// Same title as the incumbent; metadata refreshed, no rename.
        case refreshedMetadata
        case rejectedManualTitle
        case rejectedLowConfidence
        case rejectedWeakerSource
        case rejectedWithinDwell
        case rejectedInsufficientMargin
    }

    public var policy: Policy

    public init(policy: Policy = .default) {
        self.policy = policy
    }

    /// Apply an observation to a context, returning the new context and why.
    @discardableResult
    public func apply(
        _ observation: ContextObservation,
        to context: inout TabContext,
        at now: Date = Date()
    ) -> Decision {
        guard context.isAutoNamingEnabled, context.manualTitle == nil else {
            return .rejectedManualTitle
        }
        guard observation.confidence >= policy.minimumConfidence else {
            return .rejectedLowConfidence
        }

        guard let currentTitle = context.generatedTitle else {
            adopt(observation, into: &context, at: now)
            return .accepted
        }

        // Same title: keep the user's spatial memory intact, refresh the rest.
        if TitleFormatter.isEquivalent(currentTitle, observation.title) {
            mergeMetadata(observation, into: &context)
            context.contextConfidence = max(context.contextConfidence, observation.confidence)
            return .refreshedMetadata
        }

        if observation.source > context.contextSource {
            // A detected agent task outranks "the foreground process is node".
            guard observation.confidence >= policy.preemptionConfidence else {
                return .rejectedLowConfidence
            }
            adopt(observation, into: &context, at: now)
            return .accepted
        }

        if observation.source < context.contextSource {
            // Never demote: a shell prompt returning does not erase the task
            // the tab was opened to do.
            return .rejectedWeakerSource
        }

        // Same source, different title — this is the churn case.
        guard now.timeIntervalSince(context.lastContextUpdate) >= policy.minimumDwell else {
            return .rejectedWithinDwell
        }
        guard observation.confidence >= context.contextConfidence + policy.replacementMargin else {
            return .rejectedInsufficientMargin
        }
        adopt(observation, into: &context, at: now)
        return .accepted
    }

    private func adopt(_ observation: ContextObservation, into context: inout TabContext, at now: Date) {
        context.generatedTitle = observation.title
        context.contextSource = observation.source
        context.contextConfidence = observation.confidence
        context.lastContextUpdate = now
        mergeMetadata(observation, into: &context)
    }

    private func mergeMetadata(_ observation: ContextObservation, into context: inout TabContext) {
        if let task = observation.activeTask { context.activeTask = task }
        if let process = observation.processName { context.processName = process }
        if let project = observation.projectName { context.projectName = project }
        if let directory = observation.workingDirectory { context.workingDirectory = directory }
    }
}
