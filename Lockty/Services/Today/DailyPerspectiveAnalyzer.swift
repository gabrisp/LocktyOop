import Foundation

struct DailyPerspectiveInput: Codable, Hashable {
    var productivityScore: Int
    var controlScore: Int
    var detoxScore: Int
    var mostProductivePeriodText: String
    var distractionPeriodText: String
    var leadingDistractionApps: [String]
}

protocol DailyPerspectiveAnalyzing {
    func perspective(from input: DailyPerspectiveInput) -> DailyPerspective
}

struct DailyPerspectiveAnalyzer: DailyPerspectiveAnalyzing {
    func perspective(from input: DailyPerspectiveInput) -> DailyPerspective {
        let average = (input.productivityScore + input.controlScore + input.detoxScore) / 3
        let appText = input.leadingDistractionApps.prefix(2).joined(separator: " and ")

        switch average {
        case 80...100:
            return DailyPerspective(
                id: "primary",
                title: "Great day",
                body: "\(input.productivityScore)% of your phone usage was intentional, and your strongest period was \(input.mostProductivePeriodText). Distractions stayed controlled after \(input.distractionPeriodText).",
                tone: .excellent
            )
        case 70..<80:
            return DailyPerspective(
                id: "primary",
                title: "Strong morning",
                body: "Your most productive period was \(input.mostProductivePeriodText). Distractions increased after \(input.distractionPeriodText), mostly from \(appText).",
                tone: .focused
            )
        case 45..<70:
            return DailyPerspective(
                id: "primary",
                title: "Balanced day",
                body: "You had clear focused periods, but distraction picked up after \(input.distractionPeriodText). \(appText) created the biggest drift.",
                tone: .balanced
            )
        default:
            return DailyPerspective(
                id: "primary",
                title: "High distraction",
                body: "Your day had more reactive usage than planned usage. The main pattern was repeated distraction after \(input.distractionPeriodText).",
                tone: .highDistraction
            )
        }
    }
}
