import SwiftUI
import MultipeerConnectivity

/// Local multiplayer: friends nearby open Emu4ios and use their iPhone as player 2, 3 or 4.
/// Works over Wi-Fi or Bluetooth without the internet (Multipeer Connectivity).
@MainActor
final class ControllerLink: NSObject, ObservableObject {
    static let shared = ControllerLink()
    static let serviceType = "emu4ios-pad"

    // MARK: Host (the phone running the game)

    @Published private(set) var hosting = false
    @Published private(set) var players: [MCPeerID: Int] = [:]   // peer → port (1…3)
    /// Input from guests: (port, buttons, left stick, right stick).
    var onInput: ((Int, UInt32, SIMD2<Double>, SIMD2<Double>) -> Void)?

    // MARK: Guest (the phone used as a controller)

    @Published private(set) var nearbyHosts: [MCPeerID] = []
    @Published private(set) var connectedHost: MCPeerID?
    @Published private(set) var guestSystem: GameSystem?
    @Published private(set) var guestPort = 1
    @Published var guestError: String?

    private let peer = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var hostSystem: GameSystem = .gba

    private func makeSession() -> MCSession {
        let s = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        session = s
        return s
    }

    // MARK: Hosting

    func startHosting(system: GameSystem) {
        stop()
        hostSystem = system
        _ = makeSession()
        let adv = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["system": system.rawValue], serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        hosting = true
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        hosting = false
        for port in players.values { onInput?(port, 0, .zero, .zero) }
        players = [:]
        nearbyHosts = []
        connectedHost = nil
        guestSystem = nil
    }

    private func nextFreePort() -> Int? { (1...3).first { !players.values.contains($0) } }

    // MARK: Being a controller

    func startBrowsing() {
        stop()
        _ = makeSession()
        let b = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
    }

    func join(_ host: MCPeerID) {
        guard let session, let browser else { return }
        guestError = nil
        browser.invitePeer(host, to: session, withContext: nil, timeout: 20)
    }

    /// Sends this controller's state to the host (called on every change).
    func send(buttons: UInt32, left: SIMD2<Double> = .zero, right: SIMD2<Double> = .zero) {
        guard let session, let host = connectedHost else { return }
        var packet = Packet(kind: 1, port: UInt8(guestPort), buttons: buttons,
                            lx: Int16(left.x * 32767), ly: Int16(left.y * 32767),
                            rx: Int16(right.x * 32767), ry: Int16(right.y * 32767))
        let data = Data(bytes: &packet, count: MemoryLayout<Packet>.size)
        try? session.send(data, toPeers: [host], with: .unreliable)
    }

    /// Fixed-size message: kind 1 = input (guest → host), kind 2 = welcome (host → guest, port + system).
    struct Packet {
        var kind: UInt8
        var port: UInt8
        var buttons: UInt32
        var lx: Int16, ly: Int16, rx: Int16, ry: Int16
        var system: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private func welcome(_ peerID: MCPeerID, port: Int) {
        var packet = Packet(kind: 2, port: UInt8(port), buttons: 0, lx: 0, ly: 0, rx: 0, ry: 0)
        withUnsafeMutableBytes(of: &packet.system) { raw in
            for (i, b) in hostSystem.rawValue.utf8.prefix(12).enumerated() { raw[i] = b }
        }
        let data = Data(bytes: &packet, count: MemoryLayout<Packet>.size)
        try? session?.send(data, toPeers: [peerID], with: .reliable)
    }

    fileprivate func received(_ data: Data, from peerID: MCPeerID) {
        guard data.count == MemoryLayout<Packet>.size else { return }
        var packet = Packet(kind: 0, port: 0, buttons: 0, lx: 0, ly: 0, rx: 0, ry: 0)
        withUnsafeMutableBytes(of: &packet) { _ = data.copyBytes(to: $0) }
        switch packet.kind {
        case 1 where hosting:
            guard let port = players[peerID] else { return }
            func v(_ x: Int16, _ y: Int16) -> SIMD2<Double> { SIMD2(Double(x) / 32767, Double(y) / 32767) }
            onInput?(port, packet.buttons, v(packet.lx, packet.ly), v(packet.rx, packet.ry))
        case 2 where !hosting:
            guestPort = Int(packet.port)
            let name = withUnsafeBytes(of: &packet.system) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guestSystem = GameSystem(rawValue: name) ?? .gba
        default:
            break
        }
    }
}

extension ControllerLink: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if hosting {
                    guard let port = nextFreePort() else { session.cancelConnectPeer(peerID); return }
                    players[peerID] = port
                    welcome(peerID, port: port)
                } else {
                    connectedHost = peerID
                    browser?.stopBrowsingForPeers()
                }
            case .notConnected:
                if hosting, let port = players.removeValue(forKey: peerID) {
                    onInput?(port, 0, .zero, .zero) // let go of everything
                }
                if connectedHost == peerID {
                    connectedHost = nil
                    guestSystem = nil
                    guestError = "Disconnected from \(peerID.displayName)"
                    browser?.startBrowsingForPeers()
                }
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.received(data, from: peerID) }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            let accept = hosting && nextFreePort() != nil
            invitationHandler(accept, accept ? session : nil)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in if !nearbyHosts.contains(peerID) { nearbyHosts.append(peerID) } }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in nearbyHosts.removeAll { $0 == peerID } }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in guestError = "Couldn't search for games: \(error.localizedDescription)" }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in hosting = false }
    }
}

// MARK: - Views

/// "Use this iPhone as a controller" — find a nearby game and play as player 2–4.
struct ControllerModeView: View {
    @ObservedObject var link = ControllerLink.shared
    @EnvironmentObject var themes: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var held: [String: UInt32] = [:]
    @State private var left = SIMD2<Double>.zero
    @State private var right = SIMD2<Double>.zero

    var body: some View {
        Group {
            if let system = link.guestSystem, link.connectedHost != nil {
                controller(system)
            } else {
                NavigationStack {
                    List {
                        Section {
                            if link.nearbyHosts.isEmpty {
                                HStack { ProgressView(); Text("Looking for games nearby…").foregroundStyle(.secondary) }
                            }
                            ForEach(link.nearbyHosts, id: \.self) { host in
                                Button { link.join(host) } label: {
                                    Label(host.displayName, systemImage: "iphone.gen3.radiowaves.left.and.right")
                                }
                            }
                        } footer: {
                            Text("On the phone running the game, open the menu and tap Invite Players. Both phones need Wi-Fi or Bluetooth on.")
                        }
                        if let error = link.guestError {
                            Text(error).foregroundStyle(.red).font(.footnote)
                        }
                    }
                    .navigationTitle("Be a Controller")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                }
            }
        }
        .onAppear { link.startBrowsing() }
        .onDisappear { link.stop() }
    }

    private func controller(_ system: GameSystem) -> some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            var layout = themes.active.controller(for: system).layout(landscape: landscape)
            // No game screen here, so remove app-only buttons and keep a way out.
            let _ = layout.buttons.removeAll { $0.input.isAction }
            ZStack(alignment: .top) {
                ThemeBackground(style: themes.active.background, paused: false)
                VStack(spacing: 6) {
                    Text("Player \(link.guestPort + 1)").font(.largeTitle.bold())
                    Text("Connected to \(link.connectedHost?.displayName ?? "")").font(.subheadline).foregroundStyle(.secondary)
                    Button("Leave") { link.stop(); dismiss() }.buttonStyle(.bordered).padding(.top, 8)
                }
                .padding(.top, geo.size.height * layout.screen.y + 30)
                ControllerOverlay(layout: layout, skin: themes.active.controller(for: system), actions: ControllerActions(
                    press: { input, touch, mask, _ in held[touch] = mask ?? input.buttonMask; push() },
                    direction: { touch, mask in held[touch] = mask; push() },
                    release: { _, touch in held[touch] = nil; push() },
                    analog: { input, x, y in
                        if input == .rightStick { right = SIMD2(x, y) } else { left = SIMD2(x, y) }
                        push()
                    }))
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
    }

    private func push() {
        let buttons = held.values.reduce(0, |)
        link.send(buttons: buttons, left: left, right: right)
    }
}

/// Pause menu → Invite Players.
struct InvitePlayersView: View {
    @ObservedObject var link = ControllerLink.shared
    let system: GameSystem

    var body: some View {
        List {
            Section {
                Toggle("Let nearby phones join", isOn: Binding(
                    get: { link.hosting },
                    set: { $0 ? link.startHosting(system: system) : link.stop() }))
            } footer: {
                Text("Friends open Emu4ios → Settings → Be a Controller, then pick this phone. Up to 3 extra players.")
            }
            if !link.players.isEmpty {
                Section("Players") {
                    ForEach(link.players.sorted { $0.value < $1.value }, id: \.key) { peer, port in
                        Label("Player \(port + 1): \(peer.displayName)", systemImage: "gamecontroller.fill")
                    }
                }
            }
        }
        .navigationTitle("Invite Players")
    }
}
