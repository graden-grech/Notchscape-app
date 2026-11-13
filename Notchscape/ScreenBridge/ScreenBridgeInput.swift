// Integrated from the user-owned ScreenBridge project; see companions/ScreenBridge/PROVENANCE.md.
import Cocoa
import CoreGraphics

let SBmarker: Int64 = 0x53425247
// Windows position relative to Mac, shared by both apps.
enum SBSide: String, CaseIterable { case right,left,above,below
    var opposite: SBSide { switch self { case .right:return .left; case .left:return .right; case .above:return .below; case .below:return .above } }
}
let SBkeyMap: [Int:Int] = [0:65,1:83,2:68,3:70,4:72,5:71,6:90,7:88,8:67,9:86,11:66,12:81,13:87,14:69,15:82,16:89,17:84,18:49,19:50,20:51,21:52,22:54,23:53,24:187,25:57,26:55,27:189,28:56,29:48,30:221,31:79,32:85,33:219,34:73,35:80,36:13,37:76,38:74,39:222,40:75,41:186,42:220,43:188,44:191,45:78,46:77,47:190,48:9,49:32,50:192,51:8,53:27,65:110,67:106,69:107,71:144,75:111,76:13,78:109,81:187,82:96,83:97,84:98,85:99,86:100,87:101,88:102,89:103,91:104,92:105,96:116,97:117,98:118,99:114,100:119,101:120,103:122,105:124,106:127,107:125,109:121,111:123,113:126,64:128,79:129,80:130,90:131,114:45,115:36,116:33,117:46,118:115,119:35,120:113,121:34,122:112,123:37,124:39,125:40,126:38]
func SBdesktopBounds() -> CGRect {
    var displays = [CGDirectDisplayID](repeating:0,count:32); var count:UInt32 = 0
    CGGetActiveDisplayList(32,&displays,&count)
    return displays.prefix(Int(count)).map { CGDisplayBounds($0) }.reduce(CGRect.null) { $0.union($1) }
}
struct SBDisplayInfo {
    let id:String, name:String, bounds:CGRect, primary:Bool
    var message:[String:Any] { ["id":id,"name":name,"x":bounds.minX,"y":bounds.minY,"width":bounds.width,"height":bounds.height,"primary":primary] }
    init(id:String,name:String,bounds:CGRect,primary:Bool) { self.id=id;self.name=name;self.bounds=bounds;self.primary=primary }
    init?(_ message:[String:Any]) {
        guard let id=message["id"] as? String, let name=message["name"] as? String,
              let x=message["x"] as? Double, let y=message["y"] as? Double,
              let width=message["width"] as? Double, let height=message["height"] as? Double,
              [x,y,width,height].allSatisfy({$0.isFinite}), width>0,height>0,width<=32768,height<=32768 else { return nil }
        self.init(id:id,name:name,bounds:CGRect(x:x,y:y,width:width,height:height),primary:message["primary"] as? Bool ?? false)
    }
}
func SBlocalDisplays() -> [SBDisplayInfo] {
    var ids=[CGDirectDisplayID](repeating:0,count:32);var count:UInt32=0
    guard CGGetActiveDisplayList(32,&ids,&count) == .success else { return [] }
    return ids.prefix(Int(count)).enumerated().map { index,id in
        let screen=NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
        return SBDisplayInfo(id:String(id),name:screen?.localizedName ?? "Mac display \(index+1)",bounds:CGDisplayBounds(id),primary:id==CGMainDisplayID())
    }
}
func SBexposedEdge(_ p:CGPoint,_ r:CGRect,_ side:SBSide,_ others:[CGRect]) -> Bool {
    let probe:CGPoint
    switch side {
    case .right:guard p.x>=r.maxX-2,p.y>=r.minY,p.y<r.maxY else{return false};probe=CGPoint(x:r.maxX+1,y:p.y)
    case .left:guard p.x<=r.minX+2,p.y>=r.minY,p.y<r.maxY else{return false};probe=CGPoint(x:r.minX-1,y:p.y)
    case .above:guard p.y<=r.minY+2,p.x>=r.minX,p.x<r.maxX else{return false};probe=CGPoint(x:p.x,y:r.minY-1)
    case .below:guard p.y>=r.maxY-2,p.x>=r.minX,p.x<r.maxX else{return false};probe=CGPoint(x:p.x,y:r.maxY+1) }
    return !others.contains { $0.contains(probe) }
}
func SBdistanceToRect(_ p:CGPoint,_ r:CGRect) -> Double {
    let dx=max(r.minX-p.x,max(0,p.x-(r.maxX-1))),dy=max(r.minY-p.y,max(0,p.y-(r.maxY-1)))
    return dx*dx+dy*dy
}
func SBedgeHit(_ p:CGPoint,_ r:CGRect,_ s:SBSide,_ dx:Double,_ dy:Double) -> Bool {
    switch s { case .right: return p.x>=r.maxX-2 && dx>0
    case .left:return p.x<=r.minX+2 && dx<0
    case .above:return p.y<=r.minY+2 && dy<0
    case .below:return p.y>=r.maxY-2 && dy>0 }
}
func SBfraction(_ p:CGPoint,_ r:CGRect,_ s:SBSide) -> Double {
    let n = s == .left || s == .right ? (p.y-r.minY)/r.height : (p.x-r.minX)/r.width
    return max(0,min(1,n))
}
func SBpointOnEdge(_ n:Double,_ r:CGRect,_ s:SBSide) -> CGPoint {
    let n=max(0,min(1,n))
    switch s { case .left:return CGPoint(x:r.minX+1,y:r.minY+n*(r.height-1))
    case .right:return CGPoint(x:r.maxX-2,y:r.minY+n*(r.height-1))
    case .above:return CGPoint(x:r.minX+n*(r.width-1),y:r.minY+1)
    case .below:return CGPoint(x:r.minX+n*(r.width-1),y:r.maxY-2) }
}
final class SBInputBridge {
    var side:SBSide = .right
    var displayID:String?
    var displays:[SBDisplayInfo]=SBlocalDisplays()
    func refreshDisplays() { displays=SBlocalDisplays() }
    var connected = false
    var remote = false // our physical input controls peer
    var receiving = false // peer physical input controls us
    var send: (([String:Any])->Void)?
    var status: ((String)->Void)?
    private var tap:CFMachPort?
    private var source:CFRunLoopSource?
    private var enteredAt = Date.distantPast
    private var remoteModifiers:Set<Int> = []
    private var injectedKeys:Set<Int> = []
    private var injectedButtons:Set<Int> = []
    private var outgoingButtons:Set<Int> = []
    private var hiddenCursor=false
    private var parkedAt=CGPoint.zero
    private var selectedBounds:CGRect { displays.first(where:{$0.id==displayID})?.bounds ?? CGDisplayBounds(CGMainDisplayID()) }
    private func atBridge(_ p:CGPoint,_ r:CGRect,_ dx:Double,_ dy:Double) -> Bool {
        SBedgeHit(p,r,side,dx,dy) && SBexposedEdge(p,r,side,displays.filter{$0.bounds != r}.map{$0.bounds})
    }
    func start() -> Bool {
        if tap != nil { connected = true; return true }
        let types:[CGEventType] = [.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp,.keyDown,.keyUp,.flagsChanged,.scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1)<<$1.rawValue) }
        let callback:CGEventTapCallBack = { _,type,event,info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let bridge = Unmanaged<SBInputBridge>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                bridge.returnLocal(notify:true)
                if let tap=bridge.tap { CGEvent.tapEnable(tap:tap,enable:true) }
                return Unmanaged.passUnretained(event)
            }
            return bridge.handle(type,event) ? nil : Unmanaged.passUnretained(event)
        }
        let info=Unmanaged.passUnretained(self).toOpaque()
        // Quartz reserves the HID location for root on some macOS versions.
        // The ordinary accessibility-authorized session tap must still work.
        let earlyTap=CGEvent.tapCreate(tap:.cghidEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:callback,userInfo:info)
        guard let tap=earlyTap ?? CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:callback,userInfo:info) else { return false }
        self.tap=tap; source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
        CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
        CGEvent.tapEnable(tap:tap,enable:true); connected=true; return true
    }
    func stop() {
        returnLocal(notify:true); connected=false
        if let tap { CGEvent.tapEnable(tap:tap,enable:false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) }
        tap=nil; source=nil
    }
    func returnLocal(notify:Bool, position:Double?=nil) {
        if remote {
            remote=false
            if hiddenCursor { CGDisplayShowCursor(CGMainDisplayID());hiddenCursor=false }
            let n=position ?? 0.5
            CGWarpMouseCursorPosition(SBpointOnEdge(n,selectedBounds,side))
        }
        receiving=false; remoteModifiers.removeAll(); outgoingButtons.removeAll()
        releaseInjected()
        if notify && connected { send?(["type":"release"]) }
        status?(connected ? "Connected · controlling this Mac" : "Disconnected")
    }
    private func handle(_ type:CGEventType,_ event:CGEvent) -> Bool {
        guard connected, event.getIntegerValueField(.eventSourceUserData) != SBmarker else { return false }
        let key=Int(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyDown && key == 53 && event.flags.contains(.maskControl) && event.flags.contains(.maskAlternate) {
            returnLocal(notify:true); return true
        }
        // Local hardware takes control back from the peer immediately.
        if receiving {
            if type == .keyDown || type == .keyUp || type == .flagsChanged { return false }
            returnLocal(notify:true);return false
        }
        let moves = [.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged].contains(type)
        if moves {
            let dx=Double(event.getIntegerValueField(.mouseEventDeltaX)), dy=Double(event.getIntegerValueField(.mouseEventDeltaY))
            if remote {
                event.location=parkedAt;CGWarpMouseCursorPosition(parkedAt)
                send?(["type":"move","dx":dx,"dy":dy]);return true
            }
            let r=selectedBounds
            if Date().timeIntervalSince(enteredAt)>0.35 && outgoingButtons.isEmpty && r.insetBy(dx:-2,dy:-2).contains(event.location) && atBridge(event.location,r,dx,dy) {
                // The active event tap consumes local movement while forwarding deltas.
                // Foreground-only cursor association would require stealing app focus.
                parkedAt=SBpointOnEdge(SBfraction(event.location,r,side),r,side)
                CGWarpMouseCursorPosition(parkedAt)
                remote=true; enteredAt=Date()
                hiddenCursor=CGDisplayHideCursor(CGMainDisplayID()) == .success
                send?(["type":"enter","position":SBfraction(event.location,r,side)])
                syncModifiers(event.flags)
                status?("Connected · controlling Windows"); return true
            }
            return false
        }
        if [.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp].contains(type) {
            let button=Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let down=[.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(type)
            if down { outgoingButtons.insert(button) } else { outgoingButtons.remove(button) }
            if remote { send?(["type":"button","button":button,"down":down]); return true }
        }
        guard remote else { return false }
        if type == .flagsChanged { syncModifiers(event.flags); return true }
        if type == .keyDown || type == .keyUp {
            if let vk=SBkeyMap[key] { send?(["type":"key","key":vk,"down":type == .keyDown]) }
            return true
        }
        if type == .scrollWheel {
            send?(["type":"scroll","dy":Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))*120,"dx":Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))*120]); return true
        }
        return true
    }
    private func syncModifiers(_ flags:CGEventFlags) {
        var keys:Set<Int> = []
        if flags.contains(.maskShift) { keys.insert(16) }
        if flags.contains(.maskControl) || flags.contains(.maskCommand) { keys.insert(17) }
        if flags.contains(.maskAlternate) { keys.insert(18) }
        for key in remoteModifiers.subtracting(keys) { send?(["type":"key","key":key,"down":false]) }
        for key in keys.subtracting(remoteModifiers) { send?(["type":"key","key":key,"down":true]) }
        remoteModifiers=keys
    }
    func receive(_ msg:[String:Any]) {
        guard connected, let type=msg["type"] as? String else { return }
        let r=selectedBounds
        switch type {
        case "enter":
            // Mac wins a simultaneous crossing; the loser resumes local control.
            if remote { send?(["type":"reject"]); return }
            receiving=true; enteredAt=Date(); releaseInjected()
            CGWarpMouseCursorPosition(SBpointOnEdge(msg["position"] as? Double ?? 0.5,r,side))
            status?("Connected · Windows input controls this Mac")
        case "reject":
            if remote { returnLocal(notify:false); enteredAt=Date() }
        case "release","return":
            returnLocal(notify:false,position:msg["position"] as? Double); enteredAt=Date()
        case "move":
            guard receiving else { return }
            let dx=msg["dx"] as? Double ?? 0, dy=msg["dy"] as? Double ?? 0
            let current=CGEvent(source:nil)?.location ?? .zero
            var p=CGPoint(x:current.x+dx,y:current.y+dy)
            if injectedButtons.isEmpty && Date().timeIntervalSince(enteredAt)>0.35 && r.contains(current) && atBridge(p,r,dx,dy) {
                send?(["type":"return","position":SBfraction(p,r,side)]); receiving=false; releaseInjected(); status?("Connected · controlling this Mac"); return
            }
            if !displays.contains(where:{$0.bounds.contains(p)}),let nearest=displays.min(by:{SBdistanceToRect(p,$0.bounds)<SBdistanceToRect(p,$1.bounds)}) {
                p.x=max(nearest.bounds.minX,min(nearest.bounds.maxX-1,p.x));p.y=max(nearest.bounds.minY,min(nearest.bounds.maxY-1,p.y))
            }
            let button=injectedButtons.first ?? 0
            let eventType:CGEventType = injectedButtons.isEmpty ? .mouseMoved : (button==0 ? .leftMouseDragged : button==1 ? .rightMouseDragged : .otherMouseDragged)
            post(CGEvent(mouseEventSource:nil,mouseType:eventType,mouseCursorPosition:p,mouseButton:CGMouseButton(rawValue:UInt32(button)) ?? .left))
        case "key":
            guard receiving, let key=msg["key"] as? Int, let down=msg["down"] as? Bool else { return }
            injectKey(key,down)
        case "button":
            guard receiving, let button=msg["button"] as? Int, (0...4).contains(button), let down=msg["down"] as? Bool else { return }
            injectButton(button,down)
        case "scroll":
            guard receiving else { return }
            let dy=(msg["dy"] as? Int ?? 0)/120, dx=(msg["dx"] as? Int ?? 0)/120
            post(CGEvent(scrollWheelEvent2Source:nil,units:.line,wheelCount:2,wheel1:Int32(clamping:dy),wheel2:Int32(clamping:dx),wheel3:0))
        default:break
        }
    }
    private func flags() -> CGEventFlags {
        var flags:CGEventFlags=[]
        if injectedKeys.contains(16) { flags.insert(.maskShift) }
        if injectedKeys.contains(17) { flags.insert(.maskCommand) }
        if injectedKeys.contains(18) { flags.insert(.maskAlternate) }
        if injectedKeys.contains(91) { flags.insert(.maskControl) }
        return flags
    }
    private func injectKey(_ vk:Int,_ down:Bool) {
        let modifiers=[16:56,17:55,18:58,91:59]
        guard let code=modifiers[vk] ?? SBkeyMap.sorted(by:{$0.key<$1.key}).first(where:{$0.value==vk})?.key else { return }
        if down { injectedKeys.insert(vk) } else { injectedKeys.remove(vk) }
        let event=CGEvent(keyboardEventSource:nil,virtualKey:CGKeyCode(code),keyDown:down)
        event?.flags=flags(); post(event)
    }
    private func injectButton(_ button:Int,_ down:Bool) {
        if down { injectedButtons.insert(button) } else { injectedButtons.remove(button) }
        let type:CGEventType=button==0 ? (down ? .leftMouseDown:.leftMouseUp) : button==1 ? (down ? .rightMouseDown:.rightMouseUp) : (down ? .otherMouseDown:.otherMouseUp)
        let event=CGEvent(mouseEventSource:nil,mouseType:type,mouseCursorPosition:CGEvent(source:nil)?.location ?? .zero,mouseButton:CGMouseButton(rawValue:UInt32(button)) ?? .left)
        post(event)
    }
    private func post(_ event:CGEvent?) { event?.setIntegerValueField(.eventSourceUserData,value:SBmarker); event?.post(tap:.cghidEventTap) }
    private func releaseInjected() {
        for key in Array(injectedKeys) { injectKey(key,false) }
        for button in Array(injectedButtons) { injectButton(button,false) }
    }
}
