import AppKit
import EchoUI

if CommandLine.arguments.contains("--transcribe") {
    let code = await CLI.run(CommandLine.arguments)
    exit(code)
}

if CommandLine.arguments.contains("--capture-test") {
    exit(await CLI.captureTest(CommandLine.arguments))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
