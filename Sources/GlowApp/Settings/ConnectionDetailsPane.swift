import AppKit
import SwiftUI

/// Everything each display reports and how Glow reached it, raw codes included. The only
/// place in Glow where protocol terms appear.
struct ConnectionDetailsPane: View {
    let store: GlowStore
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button {
                        copyReport()
                    } label: {
                        ActionLabel(title: "Copy Report", symbol: "doc.on.doc")
                    }
                    .buttonStyle(ActionButtonStyle())
                } label: {
                    DetailLabel(
                        title: "Diagnostic report",
                        detail: copied
                            ? "Copied. Paste it into a support request."
                            : "Every display’s settings and how Glow reached them, as text. Serial numbers are left out."
                    )
                }
            } footer: {
                FooterNote("Raw DDC/CI codes (VCP) appear only here. A setting a display reports is never shown as tested until a read confirms it.")
            }

            ForEach(store.displays) { display in
                Section {
                    if let log = store.adapter.discoveryLog(for: display.identity) {
                        DiscoveryDetailRows(log: log, display: display)
                    }
                    ForEach(sorted(display.capabilities.filter { !$0.isUncatalogued })) { descriptor in
                        CapabilityDetailRow(descriptor: descriptor)
                    }
                    let uncatalogued = display.capabilities.filter(\.isUncatalogued).sorted { $0.sortOrder < $1.sortOrder }
                    if !uncatalogued.isEmpty {
                        UncataloguedCodeRows(descriptors: uncatalogued)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                        Text(display.name)
                        Text("\(display.connection.transport) · vendor \(hex(display.identity.vendorID)), product \(hex(display.identity.productID)), serial withheld")
                            .font(GlowTokens.Typography.caption)
                            .foregroundStyle(GlowTokens.Text.secondary)
                            .textCase(nil)
                        ForEach(display.connectionNotes, id: \.self) { note in
                            Text(note)
                                .font(GlowTokens.Typography.caption)
                                .foregroundStyle(GlowTokens.Text.secondary)
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// In OSD order, with what's listed only here after each section's OSD settings.
    private func sorted(_ capabilities: [CapabilityDescriptor]) -> [CapabilityDescriptor] {
        let order = Dictionary(uniqueKeysWithValues: CapabilityCategory.allCases.enumerated().map { ($1, $0) })
        return capabilities.sorted {
            (order[$0.category] ?? 0, $0.presentation == .osd ? 0 : 1, $0.sortOrder) < (order[$1.category] ?? 0, $1.presentation == .osd ? 0 : 1, $1.sortOrder)
        }
    }

    /// IDs as EDID tools print them, so they match what support looks up.
    private func hex(_ id: some BinaryInteger) -> String {
        "0x" + String(id, radix: 16, uppercase: true).leftPadded(to: 4)
    }

    private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.diagnosticReport(), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            copied = false
        }
    }
}

/// What DDC/CI discovery tried on one display: each profile's request and reply, the
/// profile that worked, the raw capability report and every read.
private struct DiscoveryDetailRows: View {
    let log: DDCDiscoveryLog
    let display: DisplaySnapshot

    var body: some View {
        detail("Discovery tries", lines: log.attempts.map(DDCDiscoveryLog.text(for:)) + (log.note.map { [$0] } ?? []))
        detail("Working profile", lines: [log.profileText])
        detail("Capability report", lines: [log.capabilityText], raw: log.capabilityString != nil)
        detail("Raw readings", lines: log.readings.isEmpty
            ? ["None"]
            : log.readings.map { DDCDiscoveryLog.text(for: $0, evidence: display.evidence(forCode: $0.code)) }, raw: true)
    }

    private func detail(_ title: String, lines: [String], raw: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
            Text(title)
                .font(GlowTokens.Typography.body)
                .foregroundStyle(GlowTokens.Text.primary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(raw ? GlowTokens.Typography.diagnostic : GlowTokens.Typography.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(GlowTokens.Text.secondary)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}

/// One reported capability, every fact Glow holds about it.
private struct CapabilityDetailRow: View {
    let descriptor: CapabilityDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
            HStack(alignment: .firstTextBaseline) {
                Text(descriptor.label)
                    .font(GlowTokens.Typography.body)
                    .foregroundStyle(GlowTokens.Text.primary)
                if descriptor.presentation == .connectionDetailsOnly {
                    Text("Listed here only")
                        .font(GlowTokens.Typography.caption)
                        .foregroundStyle(GlowTokens.Text.tertiary)
                } else if descriptor.presentation == .hiddenByYou {
                    StatusLabel(title: "Hidden by you", systemImage: "eye.slash")
                }
                Spacer()
                if let rawCode = descriptor.rawCode {
                    Text(rawCode)
                        .font(GlowTokens.Typography.diagnostic)
                        .foregroundStyle(GlowTokens.Text.secondary)
                } else {
                    Text("No raw code")
                        .foregroundStyle(GlowTokens.Text.tertiary)
                }
            }
            Text("Value: \(descriptor.currentValue.map { "\($0.description)\(descriptor.unit ?? "")" } ?? "No reading yet")  ·  Evidence: \(descriptor.evidence.rawValue)")
            Text("Route: \(descriptor.route.userLabel)  ·  Access: \(access)  ·  Write reliability: \(descriptor.reliability.summary)")
            Text(descriptor.reliability.lastFailure.map { "\(descriptor.reliability.provenance). \($0)" } ?? descriptor.reliability.provenance)
                .foregroundStyle(GlowTokens.Text.tertiary)
        }
        .font(GlowTokens.Typography.caption)
        .foregroundStyle(GlowTokens.Text.secondary)
        .accessibilityElement(children: .combine)
    }

    private var access: String {
        switch descriptor.access {
        case .readWrite: "read and write"
        case .readOnly: "read only"
        case .writeOnly: "write only"
        case .unavailable: "none"
        }
    }
}

/// What a display reports that Glow's catalog doesn't know: each code and its raw value. Glow
/// reads each once, at discovery or on Read Again, and never writes one (ADR 0002, decision 7).
private struct UncataloguedCodeRows: View {
    let descriptors: [CapabilityDescriptor]

    var body: some View {
        VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
            Text("Reported, not in Glow’s catalog")
                .font(GlowTokens.Typography.body)
                .foregroundStyle(GlowTokens.Text.primary)
            Text("Glow doesn’t know what these codes do, so it reads each one once, at discovery or on Read Again, and never writes them.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(GlowTokens.Typography.caption)
        .foregroundStyle(GlowTokens.Text.secondary)
        .accessibilityElement(children: .combine)
        ForEach(descriptors) { descriptor in
            VStack(alignment: .leading, spacing: GlowTokens.Space.s0_5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(descriptor.rawCode ?? descriptor.id.rawValue)
                        .font(GlowTokens.Typography.diagnostic)
                        .foregroundStyle(GlowTokens.Text.primary)
                    Text(descriptor.label)
                    Spacer()
                    Text("Read only, never written")
                        .foregroundStyle(GlowTokens.Text.tertiary)
                }
                Text(value(descriptor))
                    .font(descriptor.currentValue == nil ? GlowTokens.Typography.caption : GlowTokens.Typography.diagnostic)
                    .foregroundStyle(descriptor.currentValue == nil ? GlowTokens.Text.tertiary : GlowTokens.Text.secondary)
            }
            .font(GlowTokens.Typography.caption)
            .foregroundStyle(GlowTokens.Text.secondary)
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
        }
    }

    private func value(_ descriptor: CapabilityDescriptor) -> String {
        if let value = descriptor.currentValue { return "Raw value: \(value.description)" }
        guard let code = descriptor.reportedCode, CapabilityCatalog.readsOnce(code) else {
            return "Not read: the code is a command, not a setting."
        }
        return descriptor.reliability.lastFailure ?? "Not read yet."
    }
}

private extension CapabilityDescriptor {
    /// A reported code the catalog doesn't know, such as "vcp-e2".
    var isUncatalogued: Bool { CapabilityCatalog.uncataloguedCode(of: id) != nil }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
