import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    func point(_ name: String) -> CGPoint? {
        guard let v = axValue(name) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &p) ? p : nil
    }

    func size(_ name: String) -> CGSize? {
        guard let v = axValue(name) else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v, .cgSize, &s) ? s : nil
    }

    private func axValue(_ name: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success, let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return (value as! AXValue)
    }

    @discardableResult
    func set(_ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }

    @discardableResult
    func set(_ name: String, point: CGPoint) -> Bool {
        var p = point
        return set(name, AXValueCreate(.cgPoint, &p)!)
    }

    @discardableResult
    func set(_ name: String, size: CGSize) -> Bool {
        var s = size
        return set(name, AXValueCreate(.cgSize, &s)!)
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(self, &id) == .success && id != 0 ? id : nil
    }
}
