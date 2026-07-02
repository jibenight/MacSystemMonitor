import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let monitor = SystemMonitor()  // 3 s fermé / 1,5 s ouvert
    private let alerts = AlertEngine()
    private var lastSnapshot = SystemSnapshot()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App d'arrière-plan : pas d'icône dans le Dock.
        NSApp.setActivationPolicy(.accessory)

        // Mode capture : rend l'UI avec des données d'exemple puis quitte.
        if CommandLine.arguments.contains("--screenshot") {
            runScreenshotMode()
            return
        }

        // Icône / texte dans la barre de menu.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent",
                                   accessibilityDescription: "Moniteur Système")
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Popover contenant la vue SwiftUI. Pas de contentSize fixe :
        // l'hôte SwiftUI dimensionne lui-même le popover (évite l'espace vide).
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self  // pour basculer le mode détaillé à l'ouverture/fermeture
        let host = NSHostingController(rootView: ContentView(monitor: monitor))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        // Met à jour le texte de la barre de menu et vérifie les seuils à chaque échantillon.
        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in
                self?.lastSnapshot = snap
                self?.updateTitle(snap)
                self?.alerts.check(snap)
            }
            .store(in: &cancellables)

        // Ré-applique le titre quand les préférences d'affichage changent.
        Preferences.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateTitle(self?.lastSnapshot ?? SystemSnapshot()) }
            }
            .store(in: &cancellables)

        alerts.requestAuthorization()
        monitor.start()
    }

    /// Rend l'interface (données d'exemple) dans un PNG, puis quitte.
    private func runScreenshotMode() {
        let outPath = CommandLine.arguments.last.flatMap { $0.hasSuffix(".png") ? $0 : nil } ?? "screenshot.png"
        monitor.loadSampleData()
        // Après un tour de run loop pour laisser SwiftUI/Charts effectuer une passe de rendu.
        DispatchQueue.main.async {
            let view = ContentView(monitor: self.monitor, screenshotMode: true)
                .background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: outPath))
                print("✅ Capture écrite : \(outPath)")
            } else {
                FileHandle.standardError.write("Échec du rendu\n".data(using: .utf8)!)
            }
            NSApp.terminate(nil)
        }
    }

    private func updateTitle(_ snap: SystemSnapshot) {
        guard let button = statusItem.button else { return }
        let prefs = Preferences.shared
        var parts: [String] = []
        if prefs.showCPUInMenuBar { parts.append("CPU \(Fmt.percent(snap.cpuUsage))") }
        if prefs.showRAMInMenuBar { parts.append("RAM \(Fmt.percent(snap.memUsedRatio))") }
        // Si tout est décoché, seule l'icône reste.
        button.title = parts.isEmpty ? "" : " " + parts.joined(separator: "  ")
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - NSPopoverDelegate : cadence rapide + métriques complètes seulement quand le menu est ouvert.

    func popoverWillShow(_ notification: Notification) {
        monitor.setDetailed(true)
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.setDetailed(false)
    }
}

// Point d'entrée.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
