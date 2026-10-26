import AppKit
import SwiftUI

/// Nonactivating feedback with one anchor for its entire visible session.
final class VolumeIndicator {
    static let statusWidth: CGFloat = 76
    private var panel: NSPanel?
    private var host: NSHostingView<VolumeIndicatorView>?
    private var dismissal: DispatchWorkItem?
    private var presentation = VolumePresentation()
    private var pointerDismissal = VolumePointerDismissal()
    private weak var anchor: NSStatusBarButton?
    private var transition = 0
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onVisibilityChanged: (Bool) -> Void = { _ in }
    var frame: NSRect? { panel?.isVisible == true ? panel?.frame : nil }
    var fading: Bool { presentation.phase == .fading }
    deinit { stopMonitoring() }

    func show(_ level: VolumeLevel, anchoredTo button: NSStatusBarButton?) {
        guard level.value.isFinite, let button, let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let opening = panel?.isVisible != true
        // Capture the stable right edge before changing the item's title/width.
        let anchorRect = button.window?.convertToScreen(button.convert(button.bounds,to:nil)) ?? NSRect(x:screen.visibleFrame.maxX-24,y:screen.visibleFrame.maxY,width:0,height:0)
        presentation.update(level,time:ProcessInfo.processInfo.systemUptime)
        pointerDismissal.reset(at:NSEvent.mouseLocation)
        transition += 1
        dismissal?.cancel()
        anchor = button
        button.font = .monospacedDigitSystemFont(ofSize:NSFont.systemFontSize,weight:.regular)
        button.image = NSImage(systemSymbolName:level.muted || level.percent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",accessibilityDescription:"System volume")
        button.title = " \(level.percent)%"
        button.toolTip = "System volume: \(level.percent)% • EvenBetterTouchTool"
        if panel == nil {
            let p = NSPanel(contentRect:NSRect(x:0,y:0,width:280,height:112),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.title = "System Volume"
            p.level = .statusBar; p.hidesOnDeactivate = false; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
            let host = NSHostingView(rootView:VolumeIndicatorView(level:level))
            p.contentView = host; self.host = host; panel = p
        }
        var transaction = Transaction(animation:nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { host?.rootView = VolumeIndicatorView(level:level) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel?.animator().alphaValue = 1
        }
        if opening {
            let x = min(screen.visibleFrame.maxX-292,max(screen.visibleFrame.minX+12,anchorRect.maxX-Self.statusWidth/2-140))
            panel?.setFrameOrigin(NSPoint(x:x,y:screen.visibleFrame.maxY-124))
            panel?.orderFrontRegardless()
            onVisibilityChanged(true)
            startMonitoring()
        }
        let work = DispatchWorkItem { [weak self] in self?.dismissIfDue() }
        dismissal = work; DispatchQueue.main.asyncAfter(deadline:.now()+2,execute:work)
    }
    private func dismissIfDue() {
        guard !presentation.visible(at:ProcessInfo.processInfo.systemUptime) else { return }
        beginFade()
    }
    private func beginFade() {
        guard presentation.beginFade() else { return }
        dismissal?.cancel(); dismissal = nil
        transition += 1; let token = transition
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.transition == token, self.presentation.phase == .fading else { return }
            self.hide()
        }
    }
    func pointerMoved(to point: NSPoint) {
        if pointerDismissal.shouldDismiss(at:point) { beginFade() }
    }
    func handleEvent(_ event: NSEvent) {
        guard [.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged].contains(event.type) else { return }
        pointerMoved(to:NSEvent.mouseLocation)
    }
    private func startMonitoring() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching:mask) { [weak self] in self?.handleEvent($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching:mask) { [weak self] event in self?.handleEvent(event); return event }
    }
    private func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }
    func hide() {
        let wasVisible = presentation.phase != .hidden
        transition += 1; presentation.hide()
        pointerDismissal.reset()
        dismissal?.cancel(); dismissal = nil; panel?.orderOut(nil); panel?.alphaValue = 1
        stopMonitoring()
        anchor?.title = ""; anchor?.font = .systemFont(ofSize:NSFont.systemFontSize)
        anchor?.image = NSImage(systemSymbolName:"hand.draw",accessibilityDescription:"EvenBetterTouchTool gesture controls")
        anchor?.toolTip = "EvenBetterTouchTool • Control–Option–Command–Escape disables gestures"
        if wasVisible { onVisibilityChanged(false) }
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
            GeometryReader { geometry in
                ZStack(alignment:.leading) {
                    Capsule().fill(.primary.opacity(0.15))
                    Capsule().fill(.primary).frame(width:geometry.size.width * (level.muted ? 0 : min(1,max(0,level.value))))
                }
            }.frame(height:6).transaction { $0.animation = nil; $0.disablesAnimations = true }
                .accessibilityLabel("System volume").accessibilityValue(level.muted ? "Muted" : "\(level.percent) percent")
        }.padding(22).frame(width:280,height:112).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
    }
}
