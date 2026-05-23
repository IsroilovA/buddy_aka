import Foundation

public struct PrebuiltVoice: Sendable, Hashable, Identifiable {
    public enum Gender: String, Sendable, Hashable {
        case male
        case female
    }

    public let id: String
    public let gender: Gender
    public let descriptor: String

    public init(id: String, gender: Gender, descriptor: String) {
        self.id = id
        self.gender = gender
        self.descriptor = descriptor
    }
}

public enum PrebuiltVoices {
    public static let curated: [PrebuiltVoice] = [
        .init(id: "Puck",   gender: .male,   descriptor: "Upbeat"),
        .init(id: "Charon", gender: .male,   descriptor: "Informative"),
        .init(id: "Fenrir", gender: .male,   descriptor: "Excitable"),
        .init(id: "Aoede",  gender: .female, descriptor: "Breezy"),
        .init(id: "Leda",   gender: .female, descriptor: "Youthful"),
        .init(id: "Zephyr", gender: .female, descriptor: "Bright"),
    ]

    public static let defaultID = "Puck"

    public static func voice(forID id: String) -> PrebuiltVoice? {
        curated.first { $0.id == id }
    }
}
