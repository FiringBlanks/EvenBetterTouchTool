import AppKit
import ApplicationServices

struct TrackpadInfo: Identifiable, Equatable {
    var id: String
    var name: String
    var rawWidth: Int32 = 0
    var rawHeight: Int32 = 0
}
/// Runtime loading and the original mt.h ABI are retained from upstream.
/// Only one selected device feeds one engine. Work is serialized off the UI thread.
final class TrackpadDriver {
    static weak var current: TrackpadDriver?
    private let queue = DispatchQueue(label: "org.evenbettertouchtool.trackpad", qos: .userInteractive)
    private var library: UnsafeMutableRawPointer?
    private var deviceList: CFMutableArray?
    private var devices: [MTDeviceRef] = []
    private var infos: [TrackpadInfo] = []
    private var activeDevice: MTDeviceRef?
    private var create: (@convention(c) () -> Unmanaged<CFMutableArray>?)?
    private var register: (@convention(c) (MTDeviceRef?, MTFrameCallbackFunction?) -> Void)?
    private var unregister: (@convention(c) (MTDeviceRef?, MTFrameCallbackFunction?) -> Void)?
    private var start: (@convention(c) (MTDeviceRef?, Int32) -> Void)?
    private var stop: (@convention(c) (MTDeviceRef?) -> Void)?
    private var engine = GestureEngine(config: .defaults, app: "", device: "")
    private var lastPublish = 0.0
    private var lastFrameReceipt = -Double.infinity
    private var reportedOtherGesture = false
    private var lastPhysicalClick = -Double.infinity
    private var mouseButtons = Set<Int64>()
    private var generation = 0
    private var clickGeneration = 0
    private var press = PressRecognizer()
    private var tapObserver: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var suspended = false
    private var observerAvailable = false
    private var scrollTap: CFMachPort?
    private var scrollSource: CFRunLoopSource?
    private var scrollFilter = ScrollFilter()
    private var permitted = false
    var onFrame: ((EngineSnapshot) -> Void)?
    var onTrigger: ((GestureTrigger, String, Int) -> Void)?
    var onDevices: (([TrackpadInfo], String) -> Void)?
    var onStatus: ((String) -> Void)?
    var onButtonObserver: ((Bool) -> Void)?
    var onScrollFiltering: ((Bool) -> Void)?
    var onOtherInteraction: (() -> Void)?
    var currentGeneration: Int { queue.sync { generation } }
    var currentClickGeneration: Int { queue.sync { clickGeneration } }
    var adjustingVolume: Bool { queue.sync { engine.adjustingVolume && ProcessInfo.processInfo.systemUptime-lastFrameReceipt < 0.12 } }
    init() { Self.current = self }
    private func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let library, let address = dlsym(library, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }
    func begin() {
        library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        create = symbol("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFMutableArray>?).self)
        register = symbol("MTRegisterContactFrameCallback", (@convention(c) (MTDeviceRef?, MTFrameCallbackFunction?) -> Void).self)
        unregister = symbol("MTUnregisterContactFrameCallback", (@convention(c) (MTDeviceRef?, MTFrameCallbackFunction?) -> Void).self)
        start = symbol("MTDeviceStart", (@convention(c) (MTDeviceRef?, Int32) -> Void).self)
        stop = symbol("MTDeviceStop", (@convention(c) (MTDeviceRef?) -> Void).self)
        guard create != nil, register != nil, unregister != nil, start != nil, stop != nil else { onStatus?("MultitouchSupport unavailable or incompatible"); return }
        installButtonObserver()
        installScrollFilter()
        reconnect()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.suspended = true; self?.disconnect() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.suspended = false
            DispatchQueue.main.asyncAfter(deadline: .now()+1) { self?.reconnect() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.suspended = true; self?.disconnect() })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.suspended = false; self?.reconnect() })
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.checkDevices() }
    }
    func configure(_ config: Configuration, app: String) {
        let needsReconnect = queue.sync { () -> Bool in
            let old = engine.config.selectedDevice
            if engine.config != config { press.reset(); clickGeneration += 1 }
            engine.config = config; engine.app = app; engine.cancel("Settings or foreground app changed; lift fingers")
            updateScrollEligibility()
            generation += 1
            return old != config.selectedDevice
        }
        if needsReconnect { reconnect() }
    }
    func cancel() { queue.sync { engine.cancel(); press.reset(); clickGeneration += 1; updateScrollEligibility(); generation += 1 } }
    func setPermissions(_ granted: Bool) {
        queue.sync { if permitted != granted { permitted = granted; press.reset(); clickGeneration += 1; updateScrollEligibility() } }
        if granted { installScrollFilter() }
    }
    private func updateScrollEligibility() {
        let c = engine.config
        let custom = permitted ? c.scrollInterceptedGestures(app:engine.app,device:engine.device) : []
        scrollFilter.configure(custom:custom)
    }
    func end() {
        timer?.invalidate(); timer = nil
        for token in observers { NSWorkspace.shared.notificationCenter.removeObserver(token) }; observers = []
        disconnect()
        if let tapObserver { CGEvent.tapEnable(tap: tapObserver, enable: false); CFMachPortInvalidate(tapObserver) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tapObserver = nil; tapSource = nil
        if let scrollTap { CGEvent.tapEnable(tap:scrollTap,enable:false); CFMachPortInvalidate(scrollTap) }
        if let scrollSource { CFRunLoopRemoveSource(CFRunLoopGetMain(),scrollSource,.commonModes) }
        scrollTap = nil; scrollSource = nil; onScrollFiltering?(false)
    }
    func reconnect() {
        guard !suspended else { return }
        disconnect()
        guard let list = create?()?.takeRetainedValue() else { onStatus?("No trackpad devices; check Input Monitoring"); return }
        deviceList = list
        let getID = symbol("MTDeviceGetDeviceID", (@convention(c) (MTDeviceRef?, UnsafeMutablePointer<UInt64>?) -> Int32).self)
        let dimensions = symbol("MTDeviceGetSensorSurfaceDimensions", (@convention(c) (MTDeviceRef?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Int32).self)
        var found = [TrackpadInfo]()
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0, w: Int32 = 0, h: Int32 = 0
            let identified = getID?(device, &id) == 0 && id != 0
            _ = dimensions?(device, &w, &h)
            // Without a stable ID, require fresh calibration each connection.
            let key = identified ? "mt-\(id)" : "unidentified-\(UUID().uuidString)"
            found.append(TrackpadInfo(id: key, name: "Trackpad \(i+1) • \(identified ? String(id) : "unidentified")", rawWidth: w, rawHeight: h))
            devices.append(device)
        }
        infos = found
        let configured = queue.sync { engine.config.selectedDevice }
        let index = found.firstIndex { $0.id == configured } ?? (configured.isEmpty && !found.isEmpty ? 0 : nil)
        if let index {
            let device = devices[index]
            queue.sync { activeDevice = device; engine.device = found[index].id; engine.reset(); updateScrollEligibility(); generation += 1 }
            register?(device, trackpadFrameCallback); start?(device, 0)
            onDevices?(found, found[index].id); onStatus?("Listening to selected trackpad")
        } else {
            onDevices?(found, ""); onStatus?(found.isEmpty ? "No trackpad connected / permission missing" : "Selected trackpad disconnected; choose a device")
        }
    }
    private func disconnect() {
        // Disable delivery before stopping/unregistering; queued frames cannot fire.
        let old = queue.sync { () -> MTDeviceRef? in let old = activeDevice; activeDevice = nil; engine.reset(); press.reset(); clickGeneration += 1; mouseButtons.removeAll(); lastPhysicalClick = -.infinity; scrollFilter.configure(custom:[]); generation += 1; return old }
        if let old { stop?(old); unregister?(old, trackpadFrameCallback) }
        devices = []; infos = []; deviceList = nil
        onDevices?([], ""); onStatus?("Trackpad paused / disconnected")
    }
    private func checkDevices() {
        guard !suspended else { return }
        if tapObserver == nil && CGPreflightListenEventAccess() { installButtonObserver() }
        if scrollTap == nil && AXIsProcessTrusted() && CGPreflightListenEventAccess() { installScrollFilter() }
        guard let list = create?()?.takeRetainedValue() else { return }
        let values = (0..<CFArrayGetCount(list)).compactMap { CFArrayGetValueAtIndex(list, $0) }.map { UnsafeMutableRawPointer(mutating: $0) }
        if values != devices { reconnect() }
        if !AXIsProcessTrusted() || !CGPreflightListenEventAccess() {
            queue.sync { permitted = false; engine.cancel(); press.reset(); clickGeneration += 1; updateScrollEligibility(); generation += 1 }
        }
        if let tapObserver, !CGEvent.tapIsEnabled(tap: tapObserver) { CGEvent.tapEnable(tap: tapObserver, enable: true) }
        if let scrollTap, !CGEvent.tapIsEnabled(tap:scrollTap) { CGEvent.tapEnable(tap:scrollTap,enable:true) }
        onScrollFiltering?(scrollTap.map { CGEvent.tapIsEnabled(tap:$0) } ?? false)
    }
    fileprivate func receive(device: MTDeviceRef?, contacts: [Contact], time: Double) {
        let received = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in
            guard let self, device == self.activeDevice else { return }
            self.lastFrameReceipt = received
            self.press.observe(contacts,time:received,scale:self.engine.config.movementScale(for:self.engine.device))
            let tap = self.engine.config.tapOptions(fingers:contacts.count,app:self.engine.app)
            let frame = TouchFrame(time: time, contacts: contacts, physicalButton: !self.mouseButtons.isEmpty || received-self.lastPhysicalClick < tap.clickExclusion)
            let triggers = self.engine.process(frame), app = self.engine.app, generation = self.generation
            if self.engine.trackedFingerCount == 0 { self.reportedOtherGesture = false }
            if self.engine.hasSwipeMotion && !self.engine.adjustingVolume && !self.reportedOtherGesture {
                self.reportedOtherGesture = true
                DispatchQueue.main.async { [weak self] in self?.onOtherInteraction?() }
            }
            self.scrollFilter.observe(contacts:contacts,trackedFingers:self.engine.trackedFingerCount,time:received)
            if received-self.lastPublish >= 1/20 || contacts.isEmpty {
                self.lastPublish = received
                let snapshot = self.engine.snapshot
                DispatchQueue.main.async { [weak self] in self?.onFrame?(snapshot) }
            }
            for trigger in triggers {
                guard trigger.gesture.direction != .tap || self.observerAvailable else { continue }
                let tap = self.engine.config.tapOptions(fingers:trigger.gesture.fingers,app:app)
                let delay = trigger.gesture.direction == .tap ? tap.clickDelay : 0.0
                DispatchQueue.main.asyncAfter(deadline: .now()+delay) { [weak self] in
                    guard let self else { return }
                    let valid = self.queue.sync { generation == self.generation && (trigger.gesture.direction != .tap || self.lastPhysicalClick < received-tap.clickExclusion) }
                    if trigger.gesture.direction == .tap {
                        guard let observer = self.tapObserver, CGEvent.tapIsEnabled(tap: observer) else { return }
                    }
                    guard valid, ProcessInfo.processInfo.systemUptime-received < (delay+0.12) else { return }
                    self.onTrigger?(trigger, app, generation)
                }
            }
        }
    }
    private func installScrollFilter() {
        guard library != nil, scrollTap == nil, AXIsProcessTrusted(), CGPreflightListenEventAccess() else { return }
        scrollTap = CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,
            eventsOfInterest:1 << CGEventType.scrollWheel.rawValue,callback:{ _, type, event, _ in
                guard let driver = TrackpadDriver.current else { return Unmanaged.passUnretained(event) }
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    driver.onScrollFiltering?(false)
                    driver.queue.sync { driver.scrollFilter.configure(custom:[]) }
                    if let tap = driver.scrollTap { CGEvent.tapEnable(tap:tap,enable:true) }
                    driver.queue.sync { driver.updateScrollEligibility() }
                    driver.onScrollFiltering?(driver.scrollTap.map { CGEvent.tapIsEnabled(tap:$0) } ?? false)
                    return Unmanaged.passUnretained(event)
                }
                let suppress = driver.queue.sync {
                    driver.scrollFilter.suppress(time:ProcessInfo.processInfo.systemUptime,
                        continuous:event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
                        synthetic:event.getIntegerValueField(.eventSourceUnixProcessID) != 0 || event.getIntegerValueField(.eventSourceUserData) == ActionExecutor.eventTag,
                        dx:event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),dy:event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                        phase:event.getIntegerValueField(.scrollWheelEventScrollPhase),momentum:event.getIntegerValueField(.scrollWheelEventMomentumPhase))
                }
                return suppress ? nil : Unmanaged.passUnretained(event)
            },userInfo:nil)
        if let scrollTap {
            scrollSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,scrollTap,0)
            if let scrollSource { CFRunLoopAddSource(CFRunLoopGetMain(),scrollSource,.commonModes) }
            CGEvent.tapEnable(tap:scrollTap,enable:true)
        }
        onScrollFiltering?(scrollTap != nil)
    }
    private func installButtonObserver() {
        guard tapObserver == nil else { return }
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tapObserver = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, _ in
            if event.getIntegerValueField(.eventSourceUserData) != ActionExecutor.eventTag, let driver = TrackpadDriver.current {
                let down = [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type)
                let button = event.getIntegerValueField(.mouseEventButtonNumber)
                let synthetic = event.getIntegerValueField(.eventSourceUnixProcessID) != 0
                let received = ProcessInfo.processInfo.systemUptime
                driver.queue.async {
                    if down { driver.mouseButtons.insert(button) } else { driver.mouseButtons.remove(button) }
                    if down { driver.lastPhysicalClick = received; driver.engine.physicalClick() }
                    let options = driver.engine.config.clickOptions(fingers:driver.press.fingers,app:driver.engine.app)
                    guard (!synthetic || !options.ignoreSynthetic), driver.permitted, driver.activeDevice != nil else { return }
                    guard let fingers = driver.press.button(Int(button),down:down,time:received,options:options) else { return }
                    let gesture = Gesture(fingers:fingers,direction:.click), app = driver.engine.app
                    let mapping = driver.engine.config.mapping(gesture,app:app), generation = driver.clickGeneration
                    guard driver.engine.config.blockedReason(gesture,mapping:mapping,device:driver.engine.device) == nil else { return }
                    driver.engine.observedPress(fingers)
                    DispatchQueue.main.async { [weak driver] in
                        guard let driver, ProcessInfo.processInfo.systemUptime-received < 0.25,
                              let observer = driver.tapObserver, CGEvent.tapIsEnabled(tap:observer) else { return }
                        driver.onTrigger?(GestureTrigger(gesture:gesture,mapping:mapping,count:1),app,generation)
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: nil)
        if let tapObserver {
            tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tapObserver, 0)
            if let tapSource { CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes) }
            CGEvent.tapEnable(tap: tapObserver, enable: true)
        }
        queue.sync { observerAvailable = tapObserver != nil }
        onButtonObserver?(tapObserver != nil)
    }
}
private let trackpadFrameCallback: MTFrameCallbackFunction = { device, touches, count, time, _ in
    guard count >= 0, count <= 16 else { TrackpadDriver.current?.cancel(); return }
    var contacts = [Contact](); contacts.reserveCapacity(4)
    if let touches {
        for i in 0..<Int(count) where touches[i].state == MTTouchState(MTTouchStateTouching) || touches[i].state == MTTouchState(MTTouchStateMakeTouch) {
            let t = touches[i]
            contacts.append(Contact(id: Int(t.identifier), x: Double(t.normalizedPosition.position.x), y: Double(t.normalizedPosition.position.y)))
        }
    }
    TrackpadDriver.current?.receive(device: device, contacts: contacts, time: time)
}
