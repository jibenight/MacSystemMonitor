import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let monitor = SystemMonitor()  // 3 s fermé / 1,5 s ouvert
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App d'arrière-plan : pas d'icône dans le Dock.
        NSApp.setActivationPolicy(.accessory)

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

        // Met à jour le texte de la barre de menu à chaque échantillon.
        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in
                self?.updateTitle(snap)
            }
            .store(in: &cancellables)

        monitor.start()
    }

    private func updateTitle(_ snap: SystemSnapshot) {
        guard let button = statusItem.button else { return }
        button.title = " CPU \(Fmt.percent(snap.cpuUsage))  RAM \(Fmt.percent(snap.memUsedRatio))"
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
