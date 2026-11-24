import AppKit
import EchoUI

if CommandLine.arguments.contains("--transcribe") {
    let code = await CLI.run(CommandLine.arguments)
    exit(code)
}

if CommandLine.arguments.contains("--capture-test") {
    exit(await CLI.captureTest(CommandLine.arguments))
}

if CommandLine.arguments.contains("--detect-language") {
    exit(await CLI.detectLanguage(CommandLine.arguments))
}

if CommandLine.arguments.contains("--translate") {
    exit(await CLI.translate(CommandLine.arguments))
}

if CommandLine.arguments.contains("--notes") {
    exit(await CLI.notes(CommandLine.arguments))
}

if CommandLine.arguments.contains("--interpret-test") {
    exit(await CLI.interpretTest(CommandLine.arguments))
}

if CommandLine.arguments.contains("--soak") {
    exit(await CLI.soak(CommandLine.arguments))
}

if CommandLine.arguments.contains("--detect-calls") {
    exit(CLI.detectCalls())
}

if CommandLine.arguments.contains("--dub-test") {
    exit(await CLI.dubTest(CommandLine.arguments))
}

if CommandLine.arguments.contains("--translate-bench") {
    exit(await CLI.translateBench())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
