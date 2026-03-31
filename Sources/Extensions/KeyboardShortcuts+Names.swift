import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static func spaceSlot(_ index: Int) -> Self {
        Self("activateSpace\(index)")
    }

    static let activateSpace0 = Self("activateSpace0",
        default: .init(.one, modifiers: [.control, .option]))
    static let activateSpace1 = Self("activateSpace1",
        default: .init(.two, modifiers: [.control, .option]))
    static let activateSpace2 = Self("activateSpace2",
        default: .init(.three, modifiers: [.control, .option]))
    static let activateSpace3 = Self("activateSpace3",
        default: .init(.four, modifiers: [.control, .option]))
    static let activateSpace4 = Self("activateSpace4",
        default: .init(.five, modifiers: [.control, .option]))
    static let activateSpace5 = Self("activateSpace5",
        default: .init(.six, modifiers: [.control, .option]))
    static let activateSpace6 = Self("activateSpace6",
        default: .init(.seven, modifiers: [.control, .option]))
    static let activateSpace7 = Self("activateSpace7",
        default: .init(.eight, modifiers: [.control, .option]))
    static let activateSpace8 = Self("activateSpace8",
        default: .init(.nine, modifiers: [.control, .option]))
}
