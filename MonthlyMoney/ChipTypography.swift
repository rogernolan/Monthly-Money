import SwiftUI

enum ChipTypography {
    static func monthValueFontSize(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .regular ? 38 : 25.5
    }

    static func dailyValueFontSize(for sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .regular ? 40 : 28
    }
}
