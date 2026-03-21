import SwiftUI

struct ChipPalette: Equatable {
    let titleColor: Color
    let valueColor: Color
    let plainTop: Color
    let plainBottom: Color
    let plainBorder: Color
    let negativeTop: Color
    let negativeBottom: Color

    static func forColorScheme(_ colorScheme: ColorScheme) -> ChipPalette {
        switch colorScheme {
        case .dark:
            return ChipPalette(
                titleColor: Color.black.opacity(0.65),
                valueColor: .black,
                plainTop: Color(red: 0.86, green: 0.86, blue: 0.86),
                plainBottom: Color(red: 0.80, green: 0.80, blue: 0.80),
                plainBorder: Color.black.opacity(0.18),
                negativeTop: Color(red: 0.98, green: 0.90, blue: 0.90),
                negativeBottom: Color(red: 0.94, green: 0.78, blue: 0.78)
            )
        default:
            return ChipPalette(
                titleColor: .secondary,
                valueColor: .primary,
                plainTop: .white,
                plainBottom: Color(red: 0.96, green: 0.96, blue: 0.96),
                plainBorder: Color.black.opacity(0.15),
                negativeTop: Color(red: 0.98, green: 0.86, blue: 0.86),
                negativeBottom: Color(red: 0.93, green: 0.70, blue: 0.70)
            )
        }
    }
}
