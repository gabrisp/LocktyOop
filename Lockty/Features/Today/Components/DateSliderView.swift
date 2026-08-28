import SwiftUI
import UIKit

enum DayPageSliderMetrics {
    static let itemWidth: CGFloat = 60
    static let height: CGFloat = 50
    static let barHeight: CGFloat = 62
}

struct DayPageSlider<Content: View>: UIViewRepresentable {
    var content: Content

    @Binding var offset: CGFloat
    let pickerCount: Int
    let selectedIndex: Int?
    let onIndexChanged: (Int) -> Void
    let width: CGFloat
    let onSelectionChanged: () -> Void

    init(
        pickerCount: Int,
        offset: Binding<CGFloat>,
        width: CGFloat,
        selectedIndex: Int?,
        onIndexChanged: @escaping (Int) -> Void,
        onSelectionChanged: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self._offset = offset
        self.pickerCount = pickerCount
        self.selectedIndex = selectedIndex
        self.onIndexChanged = onIndexChanged
        self.width = width
        self.onSelectionChanged = onSelectionChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        let hostingController = UIHostingController(rootView: content)
        let hostedView = hostingController.view!

        context.coordinator.hostingController = hostingController
        hostedView.backgroundColor = .clear
        hostingController.view.backgroundColor = .clear

        scrollView.addSubview(hostedView)
        scrollView.bounces = false
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = context.coordinator

        configure(scrollView, hostedView: hostedView)
        if let selectedIndex {
            scrollView.setContentOffset(targetOffset(for: selectedIndex), animated: false)
        }

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self

        guard let hostingController = context.coordinator.hostingController else { return }
        hostingController.rootView = content
        hostingController.view.backgroundColor = .clear

        configure(scrollView, hostedView: hostingController.view)

        guard
            let selectedIndex,
            selectedIndex >= 0,
            selectedIndex < pickerCount,
            !context.coordinator.isDragging
        else { return }

        if context.coordinator.lastSelectedIndex != selectedIndex {
            context.coordinator.lastSelectedIndex = selectedIndex
            scrollView.setContentOffset(targetOffset(for: selectedIndex), animated: true)
        }
    }

    private func configure(_ scrollView: UIScrollView, hostedView: UIView) {
        let contentWidth = CGFloat(pickerCount) * DayPageSliderMetrics.itemWidth
            + max(width - DayPageSliderMetrics.itemWidth, 0)

        hostedView.frame = CGRect(
            x: 0,
            y: 0,
            width: contentWidth,
            height: DayPageSliderMetrics.height
        )
        scrollView.contentSize = hostedView.frame.size
    }

    private func targetOffset(for index: Int) -> CGPoint {
        CGPoint(x: CGFloat(index) * DayPageSliderMetrics.itemWidth, y: 0)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: DayPageSlider
        var hostingController: UIHostingController<Content>?
        var isDragging = false
        var lastSelectedIndex: Int?
        private var lastNotifiedIndex: Int?

        init(parent: DayPageSlider) {
            self.parent = parent
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isDragging = true
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.offset = scrollView.contentOffset.x

            let index = Int((scrollView.contentOffset.x / DayPageSliderMetrics.itemWidth).rounded())
            guard index >= 0, index < parent.pickerCount, index != lastNotifiedIndex else { return }

            lastNotifiedIndex = index
            parent.onIndexChanged(index)
            parent.onSelectionChanged()
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            finishScrolling(scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else { return }
            finishScrolling(scrollView)
        }

        private func finishScrolling(_ scrollView: UIScrollView) {
            isDragging = false

            let snappedIndex = Int((scrollView.contentOffset.x / DayPageSliderMetrics.itemWidth).rounded())
            let clampedIndex = min(max(snappedIndex, 0), max(parent.pickerCount - 1, 0))
            let targetOffset = CGPoint(
                x: CGFloat(clampedIndex) * DayPageSliderMetrics.itemWidth,
                y: 0
            )

            scrollView.setContentOffset(targetOffset, animated: true)
            lastSelectedIndex = clampedIndex
            parent.onIndexChanged(clampedIndex)
            parent.onSelectionChanged()
        }
    }
}

struct DateSliderView: View {
    let dates: [Date]
    @Binding var selectedDate: Date
    @Binding var scrollOffset: CGFloat
    var onDateChanged: ((Date) -> Void)?
    var onSelectionChanged: () -> Void
    var horizontalPadding: CGFloat = LocktySpacing.md

    private var selectedIndex: Int? {
        dates.firstIndex { Calendar.current.isDate($0, inSameDayAs: selectedDate) }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - horizontalPadding * 2, DayPageSliderMetrics.itemWidth)

            DayPageSlider(
                pickerCount: dates.count,
                offset: $scrollOffset,
                width: width,
                selectedIndex: selectedIndex,
                onIndexChanged: selectDate(at:),
                onSelectionChanged: onSelectionChanged
            ) {
                sliderContent(width: width)
            }
            .frame(width: width, height: DayPageSliderMetrics.height)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: DayPageSliderMetrics.barHeight)
    }

    @ViewBuilder
    private func sliderContent(width: CGFloat) -> some View {
        let sidePadding = max((width - DayPageSliderMetrics.itemWidth) / 2, 0)

        HStack(spacing: 0) {
            ForEach(dates, id: \.timeIntervalSinceReferenceDate) { date in
                Button {
                    selectDate(date)
                } label: {
                    DateChip(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    )
                }
                .buttonStyle(.plain)
                .frame(width: DayPageSliderMetrics.itemWidth, height: DayPageSliderMetrics.height)
            }
        }
        .padding(.horizontal, sidePadding)
    }

    private func selectDate(at index: Int) {
        guard dates.indices.contains(index) else { return }
        selectDate(dates[index])
    }

    private func selectDate(_ date: Date) {
        guard !Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return }

        withAnimation(.smooth(duration: 0.24)) {
            selectedDate = date
            onDateChanged?(date)
        }
    }
}

private struct DateChip: View {
    let date: Date
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(date, format: .dateTime.day())
                .font(.system(size: 18, weight: .black, design: .default))
                .monospacedDigit()

            Text(date, format: .dateTime.month(.abbreviated))
                .font(.system(size: 11, weight: .semibold, design: .default))
                .textCase(.uppercase)
        }
        .foregroundStyle(isSelected ? LocktyColors.primaryText : LocktyColors.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(.smooth(duration: 0.24), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
