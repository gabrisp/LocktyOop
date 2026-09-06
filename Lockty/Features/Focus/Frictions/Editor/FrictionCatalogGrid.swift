import SwiftUI

/// The catalogue as a grid of miniatures.
///
/// The list catalogue is still there and still works; this is the other way of choosing.
/// A row with a glyph and a sentence tells you what a friction is *called*, which is the
/// least useful thing about it -- what you actually want to know is what the screen will
/// look like when it stops you, and the only honest way to show that is to show it.
///
/// Each cell renders the real step view, scaled down and inert. Not a drawing of one: a
/// picture would drift the first time a step changed, and this cannot.
struct FrictionCatalogGrid: View {
    let onSelect: (FrictionCatalogItem) -> Void

    @State private var filter: FrictionCategory?

    private var items: [FrictionCatalogItem] {
        guard let filter else { return FrictionCatalog.items }
        return FrictionCatalog.items.filter { $0.category == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            filters

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: LocktySpacing.md), count: 3),
                spacing: LocktySpacing.md
            ) {
                ForEach(items) { item in
                    cell(item)
                        .transition(.blurReplace.combined(with: .opacity))
                }
            }
            .padding(.horizontal, LocktySpacing.screenInset)
        }
        .animation(.smooth(duration: 0.3), value: filter)
    }

    /// The filter row scrolls edge to edge with the padding on its contents, not on the
    /// scroll view: padding the view itself cuts the chips off at the inset instead of
    /// letting them run under it.
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LocktySpacing.sm) {
                chip(title: "All", isSelected: filter == nil) { filter = nil }

                ForEach(FrictionCategory.allCases) { category in
                    chip(title: category.title, isSelected: filter == category) {
                        filter = filter == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.screenInset)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { action() }
        } label: {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(isSelected ? LocktyColors.onPrimary : LocktyColors.primaryText)
                .padding(.horizontal, LocktySpacing.lg)
                .frame(height: 40)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? LocktyColors.primaryText : LocktyColors.ink(0.06))
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
        .tappable()
    }

    /// A miniature of the real screen, with its name under it.
    ///
    /// Scaled rather than laid out small: a step given a hundred points to work with
    /// would re-wrap its text and rearrange its grid, and the point of the thumbnail is
    /// that it is the same shape you will meet.
    private func cell(_ item: FrictionCatalogItem) -> some View {
        Button {
            onSelect(item)
        } label: {
            VStack(spacing: LocktySpacing.sm) {
                FrictionStepThumbnail(
                    // The constant, not a freshly minted step. `makeStep()` mints a new
                    // UUID every time the body runs, which is a new identity for the
                    // preview on every redraw -- so every `task(id:)` inside it restarted
                    // and the grid rebuilt itself continuously while you scrolled.
                    step: FrictionPreviewSteps.step(for: item.kind),
                    tint: item.tint,
                    index: items.firstIndex(where: { $0.id == item.id }) ?? 0
                )

                Text(item.title)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
            }
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }
}

/// One step, drawn at a fraction of its size and unable to be touched.
///
/// The whole flow view is rendered inside a fixed frame and scaled down, which is what
/// makes it a preview rather than an illustration: it cannot say something the step does
/// not, and it cannot fall out of date.
struct FrictionStepThumbnail: View {
    /// Nil for the kinds with nothing worth previewing, which rest on their glyph.
    let step: FrictionStep?
    let tint: Color
    /// Where it sits in the grid, used only to stagger the build.
    var index: Int = 0

    /// The size the step is laid out at before being shrunk: a phone, at a phone's
    /// shape. The width is what makes text wrap where it will wrap; the height is what
    /// makes the miniature look like a screen rather than a letterbox of one.
    private let renderedWidth: CGFloat = 340
    private var renderedHeight: CGFloat { renderedWidth * Self.screenAspect }

    /// Roughly 19.5:9, which is every iPhone since the notch.
    static let screenAspect: CGFloat = 19.5 / 9

    @State private var status = UnlockFlowStepStatus.ready
    /// Whether the real step is built yet.
    ///
    /// A step view is not a picture: several of them start timers, deal boards and hold
    /// tasks the moment they exist. Building a screenful at once is a stutter on the way
    /// in, and keeping the ones you have scrolled past alive is a set of clocks running
    /// for nobody -- so a cell builds when it arrives and lets go when it leaves.
    @State private var isRendered = false

    /// The margin between the miniature and the edge of its cell.
    ///
    /// A step laid out edge to edge in a cell this small has its text touching the
    /// border, which reads as a screenshot that has been cropped rather than as a small
    /// screen. The gap is what makes it look like a device.
    private let inset: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let available = max(proxy.size.width - inset * 2, 1)
            let scale = available / renderedWidth

            Group {
                if isRendered {
                    content
                        .frame(width: renderedWidth, height: renderedHeight)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: available, height: renderedHeight * scale, alignment: .top)
                        .transition(.opacity)
                } else {
                    resting
                        .frame(width: available, height: renderedHeight * scale, alignment: .top)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .padding(.top, inset)
            // Inert. A thumbnail you can play is a thumbnail people will play, and the
            // flow it belongs to has not started.
            .allowsHitTesting(false)
            .disabled(true)
        }
        .task {
            guard step != nil else { return }
            // Staggered by position, so a screenful arrives in sequence rather than all
            // on the same frame. Capped: past the first row or two the delay would be
            // longer than the scroll that revealed them.
            try? await Task.sleep(for: .milliseconds(40 * min(index, 6)))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.25)) { isRendered = true }
        }
        .onDisappear { isRendered = false }
        // The cell is a screen's shape, so what is inside it is not squashed and the
        // grid reads as a row of phones.
        .aspectRatio(1 / Self.screenAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LocktyColors.ink(0.04))
        }
        .overlay {
            // A wash of the step's own colour, so a wall of miniatures is still
            // scannable: at this size the shapes inside are too small to tell apart, and
            // the tint is what the eye lands on first.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.16), .clear],
                        startPoint: .bottom,
                        endPoint: .center
                    )
                )
                .allowsHitTesting(false)
        }
        .locktyImperfectBorder(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if let step {
            UnlockFlowStepPreview(step: step, status: $status)
        } else {
            resting
        }
    }

    /// What a cell shows before its step is built, and after it has been let go. The
    /// step's own glyph on its own tint, which is what the eye lands on at this size
    /// anyway -- so the swap reads as the cell sharpening rather than as it appearing.
    private var resting: some View {
        Image(systemName: step?.symbolName ?? "square.dashed")
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(tint.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
