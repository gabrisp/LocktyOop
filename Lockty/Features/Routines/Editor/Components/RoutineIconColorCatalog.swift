import Foundation

enum RoutineIconColorCatalog {
    static let icons: [String] = [
        "house.fill",
        "bolt.fill",
        "flame.fill",
        "leaf.fill",
        "heart.fill",
        "star.fill",
        "moon.fill",
        "sun.max.fill",
        "sparkles",
        "timer",
        "clock.fill",
        "bell.fill",
        "book.fill",
        "pencil",
        "graduationcap.fill",
        "briefcase.fill",
        "list.bullet",
        "checklist",
        "target",
        "figure.walk",
        "figure.run",
        "figure.mind.and.body",
        "figure.cooldown",
        "dumbbell.fill",
        "bed.double.fill",
        "cup.and.saucer.fill",
        "fork.knife",
        "music.note",
        "headphones",
        "gamecontroller.fill",
        "camera.fill",
        "globe",
        "location.fill",
        "wifi",
        "lock.fill",
        "shield.fill",
        "hand.raised.fill",
        "message.fill",
        "brain.head.profile",
        "hands.sparkles",
        "airplane",
        "car.fill",
        "bicycle",
        "paintbrush.fill",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "leaf.arrow.circlepath",
        "drop.fill",
        "flag.fill",
        "gift.fill"
    ]

    // Matches LocktyAccent (ThemeManager.swift) exactly -- the app's accent is
    // always one of white/blue/pink, so the routine color picker offers the
    // same three instead of an unrelated palette.
    static let colors: [String] = [
        "#FFFFFF",
        "#5C9EFF",
        "#FF63AB"
    ]
}
