import Foundation

enum PunyoMaterialLibrary {
    // The one line a new material has to touch. Define it in its own file under
    // Definitions/, then add it here.
    static let all: [PunyoMaterial] = [
        .slime,
        .mochi,
        .glass,
        .sand,
        .smoke,
        .mercury,
        .bubble,
    ]

    static let starting: PunyoMaterial = .slime

    // The rare day. Mercury is the flashiest and the hardest to catch, so it is
    // the one worth it being a good day for.
    static let rare: PunyoMaterial = .mercury

    static func material(id: String) -> PunyoMaterial? {
        all.first { $0.id == id }
    }

    // Deterministic per calendar day, so "today's puni" is a fixed thing rather
    // than a reroll every launch.
    static func daily(for date: Date = Date(), calendar: Calendar = .current) -> PunyoMaterial {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        // Knuth multiplicative scramble, taken through magnitude so a negative
        // product can never bias the rare roll.
        let roll = Int((day &* 2_654_435_761).magnitude % 1000)
        if roll < 80 {
            return rare
        }
        let commons = all.filter { $0.id != rare.id }
        guard !commons.isEmpty else { return rare }
        return commons[roll % commons.count]
    }
}
