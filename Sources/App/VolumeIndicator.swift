import AppKit
import SwiftUI

/// Our own nonactivating menu-bar feedback. No Control Center UI scripting or
/// undocumented system panel APIs; showing it never changes the foreground app.
final class VolumeIndicator {
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?
    private var presentation = VolumePresentation()
    private weak var anchor: NSStatusBarButton?
    var onVisibilityChanged: (Bool) -> Void = { _ in }
    func show(_ level: VolumeLevel, anchoredTo button: NSStatusBarButton?) {
        guard let button, let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        presentation.update(level,time:ProcessInfo.processInfo.systemUptime)
        anchor = button
        button.image = NSImage(systemSymbolName:level.muted || level.percent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",accessibilityDescription:"System volume")
        button.title = " \(level.percent)%"
        button.toolTip = "System volume: \(level.percent)% • EvenBetterTouchTool"
        if panel == nil {
            let p = NSPanel(contentRect:NSRect(x:0,y:0,width:280,height:112),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.title = "System Volume"
            p.level = .statusBar; p.hidesOnDeactivate = false; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
            panel = p
        }
        panel?.contentView = NSHostingView(rootView:VolumeIndicatorView(level:level))
        let anchorRect = button.window?.convertToScreen(button.convert(button.bounds,to:nil)) ?? NSRect(x:screen.visibleFrame.maxX-24,y:screen.visibleFrame.maxY,width:0,height:0)
        let x = min(screen.visibleFrame.maxX-292,max(screen.visibleFrame.minX+12,anchorRect.midX-140))
        panel?.setFrameOrigin(NSPoint(x:x,y:screen.visibleFrame.maxY-124))
        panel?.orderFrontRegardless()
        onVisibilityChanged(true)
        dismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissIfDue() }
        dismissal = work; DispatchQueue.main.asyncAfter(deadline:.now()+2,execute:work)
    }
    private func dismissIfDue() {
        guard !presentation.visible(at:ProcessInfo.processInfo.systemUptime) else { return }
        hide()
    }
    func hide() {
        dismissal?.cancel(); dismissal = nil; panel?.orderOut(nil)
        anchor?.title = ""
        anchor?.image = NSImage(systemSymbolName:"hand.draw",accessibilityDescription:"EvenBetterTouchTool gesture controls")
        anchor?.toolTip = "EvenBetterTouchTool • Control–Option–Command–Escape disables gestures"
        onVisibilityChanged(false)
    }
}
struct VolumeIndicatorView: View {
    let level: VolumeLevel
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Image(systemName:level.muted || level.percent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                Text("System Volume").fontWeight(.semibold)
                Spacer(); Text(level.muted ? "Muted" : "\(level.percent)%").monospacedDigit()
            }
            ProgressView(value:level.muted ? 0 : min(1,max(0,level.value))).tint(.primary)
                .accessibilityLabel("System volume").accessibilityValue(level.muted ? "Muted" : "\(level.percent) percent")
        }.padding(22).frame(width:280,height:112).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
    }
}
