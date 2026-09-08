import Combine
import SwiftUI

/// A screen inside a sheet's flow, and how deep into it that screen sits.
///
/// Depth is the only thing a screen has to declare. Everything else -- which way an
/// animation runs, what "back" means -- falls out of comparing two of them.
protocol LocktyFlowStep: Hashable {
    /// How far in this screen is. The root is 0; a screen reached from another is deeper
    /// than it. Two screens reached from the same place share a depth: they are siblings,
    /// and neither is behind the other.
    var flowDepth: Int { get }
}

/// One screen replacing another inside a sheet, with the direction worked out rather than
/// declared.
///
/// These sheets have no navigation stack -- a sheet that pushes grows a bar it never asked
/// for -- so an editor swaps one screen for another and animates the swap. Which way it
/// animates is the only thing that makes the swap read as navigation instead of a glitch.
///
/// That direction was written out by hand in nine editors, each as a boolean assembled
/// from a list of conditions naming particular pairs of screens. Every such list is wrong
/// the moment a screen is inserted or the order changes, and it is wrong silently: the
/// objective editor gained a step in front of its name screen, and going back from the
/// form animated *forwards*, because no condition in its list happened to mention that
/// pair. Depth is a property of the screen itself, so the pairs never have to be
/// enumerated and adding a screen cannot break the ones already there.
@MainActor
final class LocktyFlowStack<Step: LocktyFlowStep>: ObservableObject {
    @Published private(set) var step: Step
    /// Which way the last move went, so a screen leaves the way it arrived.
    @Published private(set) var isGoingBack: Bool = false

    init(_ step: Step) {
        self.step = step
    }

    /// Moves to another screen, reading the direction off the two depths.
    ///
    /// The direction is set *outside* the animation and the screen changed inside it, and
    /// the order is the whole reason this is a class rather than a struct in `@State`.
    /// A removal transition is the one the leaving view was handed on its last render, so
    /// a direction changed in the same animated transaction as the swap never reaches it:
    /// the arriving screen animates one way and the leaving one the other.
    ///
    /// Equal depths count as forward. Siblings are not behind one another, and animating
    /// sideways-as-backwards reads as undoing something rather than as choosing.
    func move(to next: Step, animation: Animation = LocktyFlowStack.animation) {
        guard next != step else { return }
        isGoingBack = next.flowDepth < step.flowDepth
        withAnimation(animation) { step = next }
    }

    /// Going in slides from the right; coming back slides from the left. There is no stack
    /// here, only one screen replacing another, and the movement is what says which way
    /// you went.
    var transition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isGoingBack ? .leading : .trailing)
                .combined(with: AnyTransition(.blurReplace))
                .combined(with: .opacity),
            removal: .move(edge: isGoingBack ? .trailing : .leading)
                .combined(with: AnyTransition(.blurReplace))
                .combined(with: .opacity)
        )
    }

    /// The one animation every screen swap uses, so two editors cannot disagree about how
    /// fast the same gesture feels.
    ///
    /// `nonisolated` because it is the default for `move(to:)`'s animation argument, and a
    /// default argument is evaluated at the call site rather than inside the actor.
    /// Computed rather than stored because a generic type may not hold a static stored
    /// property -- there would be one per `Step`, and Swift will not lay that out.
    nonisolated static var animation: Animation { .snappy(duration: 0.4, extraBounce: 0.02) }
}
