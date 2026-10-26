import AppKit
import SwiftUI

/// Nonactivating feedback with one anchor for its entire visible session.
final class VolumeIndicator {
    static let statusWidth: CGFloat = 76
    private var panel: NSPanel?
    private var host: NSHostingView<VolumeIndicatorView>?
    private var dismissal: DispatchWorkItem?
    private var presentation = VolumePresentation()
    private weak var anchor: NSStatusBarButton?
    private var transition = 0
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    var onVisibilityChanged: (Bool) -> Void = { _ in }
    var isVolumeGesture: () -> Bool = { false }
    var frame: NSRect? { panel?.isVisible == true ? panel?.frame : nil }
    var fading: Bool { presentation.phase == .fading }
    deinit { stopMonitoring() }

    func show(_ level: VolumeLevel, anchoredTo button: NSStatusBarButton?) {
        guard level.value.isFinite, let button, let screen = button.window?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let opening = panel?.isVisible != true
        // Capture the stable right edge before changing the item's title/width.
        let anchorRect = button.window?.convertToScreen(button.convert(button.bounds,to:nil)) ?? NSRect(x:screen.visibleFrame.maxX-24,y:screen.visibleFrame.maxY,width:0,height:0)
        presentation.update(level,time:ProcessInfo.processInfo.systemUptime)
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
        dismissForInteraction()
    }
    func dismissForInteraction() {
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
    private func interact(_ event: NSEvent) {
        if event.type == .scrollWheel {
            // Gesture tails are continuations, not a new user action.
            if !event.momentumPhase.isEmpty || event.phase.contains(.ended) || event.phase.contains(.cancelled) { return }
            if isVolumeGesture() { return }
        }
        dismissForInteraction()
    }
    private func startMonitoring() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,
            .leftMouseDown,.rightMouseDown,.otherMouseDown,.leftMouseUp,.rightMouseUp,.otherMouseUp,
            .keyDown,.keyUp,.flagsChanged,.scrollWheel,.magnify,.rotate]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching:mask) { [weak self] in self?.interact($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching:mask) { [weak self] event in self?.interact(event); return event }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] _ in self?.dismissForInteraction() }
    }
    private func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        globalMonitor = nil; localMonitor = nil; activationObserver = nil
    }
    func hide() {
        let wasVisible = presentation.phase != .hidden
        transition += 1; presentation.hide()
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
