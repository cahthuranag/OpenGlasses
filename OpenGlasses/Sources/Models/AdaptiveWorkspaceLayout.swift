import Foundation
import CoreGraphics

/// Layout is a function of the scene's usable space, never its device name or orientation.
struct AdaptiveWorkspaceLayout: Equatable {
    let contextWidth: CGFloat
    let isShort: Bool

    var showsContext: Bool { contextWidth > 0 }
    static let compact = Self(contextWidth: 0, isShort: false)
    static let columnSpacing: CGFloat = 12

    static func resolve(size: CGSize, minimumPrimaryWidth: CGFloat = 340,
                        minimumContextWidth: CGFloat = 280,
                        accessibilityText: Bool = false) -> Self {
        let short = size.height < 440
        guard size.width.isFinite, size.height.isFinite,
              size.height > 0, !accessibilityText,
              size.width >= minimumPrimaryWidth + minimumContextWidth + columnSpacing else {
            return Self(contextWidth: 0, isShort: short)
        }
        let context = min(420, max(minimumContextWidth, (size.width - columnSpacing) * 0.44))
        return Self(contextWidth: min(context, size.width - columnSpacing - minimumPrimaryWidth),
                    isShort: short)
    }

    /// A short window must keep a complete action row and the persistent Talk/Stop control.
    /// Larger windows leave a readable conversation above a dock of at most two resting rows.
    func dockReservation(availableHeight: CGFloat, measuredSurface: CGFloat?) -> CGFloat? {
        guard showsContext else { return measuredSurface }
        return max(0, availableHeight - (isShort ? 250 : 340))
    }
}

/// Frames are local to the current view. A division comes from the system's reserved-region
/// API; neither device names nor an assumed fold position participate in this decision.
struct AdaptiveWorkspacePlacement: Equatable {
    let primary: CGRect
    let context: CGRect?

    var layout: AdaptiveWorkspaceLayout {
        AdaptiveWorkspaceLayout(contextWidth: context?.width ?? 0,
                                isShort: primary.height < 440 || (context.map { $0.maxY <= primary.minY } ?? false))
    }

    static func resolve(size: CGSize, minimumPrimaryWidth: CGFloat = 340,
                        minimumContextWidth: CGFloat = 280, accessibilityText: Bool = false,
                        rightToLeft: Bool = false, divisions: [CGRect] = []) -> Self {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return Self(primary: .zero, context: nil)
        }
        let bounds = CGRect(origin: .zero, size: size)
        let division = divisions.first { frame in
            [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
                && !frame.intersection(bounds).isEmpty && !frame.intersection(bounds).isNull
        }?.intersection(bounds)

        if let division {
            if division.height >= division.width {
                let left = CGRect(x: 0, y: 0, width: division.minX, height: size.height)
                let right = CGRect(x: division.maxX, y: 0,
                                   width: size.width - division.maxX, height: size.height)
                let leading = rightToLeft ? right : left
                let trailing = rightToLeft ? left : right
                if !accessibilityText, leading.width >= minimumPrimaryWidth,
                   trailing.width >= minimumContextWidth {
                    return Self(primary: leading, context: trailing)
                }
                return Self(primary: leading.width >= trailing.width ? leading : trailing, context: nil)
            }
            let upper = CGRect(x: 0, y: 0, width: size.width, height: division.minY)
            let lower = CGRect(x: 0, y: division.maxY, width: size.width,
                               height: size.height - division.maxY)
            // Controls belong on the stable lower surface, with job/reference content above.
            if !accessibilityText, size.width >= max(minimumPrimaryWidth, minimumContextWidth),
               lower.height >= 300, upper.height >= 260 {
                return Self(primary: lower, context: upper)
            }
            return Self(primary: lower.height >= upper.height ? lower : upper, context: nil)
        }

        let layout = AdaptiveWorkspaceLayout.resolve(
            size: size, minimumPrimaryWidth: minimumPrimaryWidth,
            minimumContextWidth: minimumContextWidth, accessibilityText: accessibilityText)
        guard layout.showsContext else { return Self(primary: bounds, context: nil) }
        let primaryWidth = size.width - layout.contextWidth - AdaptiveWorkspaceLayout.columnSpacing
        return Self(
            primary: CGRect(x: rightToLeft ? size.width - primaryWidth : 0, y: 0,
                            width: primaryWidth, height: size.height),
            context: CGRect(x: rightToLeft ? 0 : size.width - layout.contextWidth, y: 0,
                            width: layout.contextWidth, height: size.height))
    }
}
