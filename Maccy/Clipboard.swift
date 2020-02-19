import AppKit
import Carbon

class Clipboard {
  typealias OnNewCopyHook = (String) -> Void
  typealias OnRemovedCopyHook = () -> Void

  private let pasteboard = NSPasteboard.general
  private let timerInterval = 1.0

  // See http://nspasteboard.org for more details.
  private let ignoredTypes: Set = [
    "org.nspasteboard.TransientType",
    "org.nspasteboard.ConcealedType",
    "org.nspasteboard.AutoGeneratedType",
    "de.petermaurer.TransientPasteboardType",
    "com.typeit4me.clipping",
    "Pasteboard generator type",
    "com.agilebits.onepassword"
  ]

  private var changeCount: Int
  private var onNewCopyHooks: [OnNewCopyHook]
  private var onRemovedCopyHooks: [OnRemovedCopyHook]

  init() {
    changeCount = pasteboard.changeCount
    onNewCopyHooks = []
    onRemovedCopyHooks = []
  }

  func onNewCopy(_ hook: @escaping OnNewCopyHook) {
    onNewCopyHooks.append(hook)
  }

  func onRemovedCopy(_ hook: @escaping OnRemovedCopyHook) {
    onRemovedCopyHooks.append(hook)
  }

  func startListening() {
    Timer.scheduledTimer(timeInterval: timerInterval,
                         target: self,
                         selector: #selector(checkForChangesInPasteboard),
                         userInfo: nil,
                         repeats: true)
  }

  func copy(_ string: String) {
    pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
    pasteboard.setString(string, forType: NSPasteboard.PasteboardType.string)
  }

  // Based on https://github.com/Clipy/Clipy/blob/develop/Clipy/Sources/Services/PasteService.swift.
  func paste() {
    checkAccessibilityPermissions()

    DispatchQueue.main.async {
      let vCode = UInt16(kVK_ANSI_V)
      let source = CGEventSource(stateID: .combinedSessionState)
      // Disable local keyboard events while pasting
      source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                         state: .eventSuppressionStateSuppressionInterval)

      let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: true)
      let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vCode, keyDown: false)
      keyVDown?.flags = .maskCommand
      keyVUp?.flags = .maskCommand
      keyVDown?.post(tap: .cgAnnotatedSessionEventTap)
      keyVUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
  }

  @objc
  func checkForChangesInPasteboard() {
    guard pasteboard.changeCount != changeCount else {
      return
    }

    // Some applications add 2 items to pasteboard when copying:
    //   1. The proper meaningful string.
    //   2. The empty item with no data and types.
    // An example of such application is BBEdit.
    // To handle such cases, handle all new pasteboard items,
    // not only the last one.
    // See https://github.com/p0deje/Maccy/issues/78.
    pasteboard.pasteboardItems?.forEach({ item in
      if !shouldIgnore(item.types) {
        if let itemString = item.string(forType: .string) {
          onNewCopyHooks.forEach({ $0(itemString) })
        }
      }
    })

    changeCount = pasteboard.changeCount
  }

  private func checkAccessibilityPermissions() {
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
    AXIsProcessTrustedWithOptions(options)
  }

  private func shouldIgnore(_ types: [NSPasteboard.PasteboardType]) -> Bool {
    return !Set(types.map({ $0.rawValue })).isDisjoint(with: ignoredTypes)
  }
}
