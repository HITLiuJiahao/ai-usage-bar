import SwiftUI

/// A small compatibility layer for the Liquid Glass visual language.
///
/// macOS 26 uses SwiftUI's native Liquid Glass renderer. Earlier systems keep
/// the same translucent surface language with a material, a soft highlight,
/// and a restrained shadow so the app remains usable on macOS 13+.
extension View {
    @ViewBuilder
    func aiLiquidGlass<S: Shape>(
        tint: Color? = nil,
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                self.glassEffect(
                    .regular.tint(tint).interactive(),
                    in: shape
                )
            } else {
                self.glassEffect(
                    .regular.tint(tint),
                    in: shape
                )
            }
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(
                    color: Color.black.opacity(0.18),
                    radius: 14,
                    y: 5
                )
        }
    }

    @ViewBuilder
    func aiLiquidGlass(
        tint: Color? = nil,
        cornerRadius: CGFloat,
        interactive: Bool = false
    ) -> some View {
        aiLiquidGlass(
            tint: tint,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            interactive: interactive
        )
    }
}
