import AppKit

let app = NSApplication.shared
let statusMenu = StatusMenu()
app.delegate = statusMenu
// Menu bar only until the panel opens; Panel switches the Dock icon on and off.
app.setActivationPolicy(.accessory)
app.run()
