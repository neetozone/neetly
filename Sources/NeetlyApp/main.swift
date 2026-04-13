import AppKit

// Set the process name so the menu bar shows "neetly" instead of "neetly-app"
ProcessInfo.processInfo.performSelector(onMainThread: Selector(("setProcessName:")), with: "neetly", waitUntilDone: true)

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
