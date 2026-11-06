# Widget (Xcode only)

These sources are deliberately **outside** `InboxButler.swiftpm` because Swift
Playgrounds cannot build widget extensions. Follow "Enabling the widget" in the
root README.md. In short: add a Widget Extension target in Xcode, drop
`InboxButlerWidget/InboxButlerWidget.swift` into it, link `InboxButlerCore`,
and enable the same App Group on the app and the widget.

The app side (writing `WidgetSnapshot` and calling
`WidgetCenter.reloadAllTimelines()`) is added when the first real provider is
wired up. It must be guarded with `#if canImport(WidgetKit)` so it still
builds in Playgrounds.
