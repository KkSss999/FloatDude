import SwiftUI

/// Response states are rendered independently so a coordinator can replace
/// the stream implementation without changing this presentation surface.
struct ResponseView: View {
    let response: String
    let state: FloatingPanelState
    let onCopy: ((String) -> Void)?
    let onCancel: (() -> Void)?
    let onRetry: (() -> Void)?

    init(
        response: String,
        state: FloatingPanelState = .completed(text: ""),
        onCopy: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.response = response
        self.state = state
        self.onCopy = onCopy
        self.onCancel = onCancel
        self.onRetry = onRetry
    }

    private var visibleResponse: String {
        guard let stateResponse = state.responseText else { return response }
        return stateResponse.isEmpty ? response : stateResponse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label("Response", systemImage: state.headerSymbolName)
                .font(.headline)
            Spacer(minLength: 8)
            Text(state.statusTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Status: \(state.statusTitle)")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading(let action):
            statusCard {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing \(action.title)…")
            }
        case .streaming:
            responseText(visibleResponse)
                .overlay(alignment: .topTrailing) {
                    ProgressView()
                        .controlSize(.small)
                        .padding(12)
                        .accessibilityLabel("Generating")
                }
        case .completed:
            responseText(visibleResponse)
        case .cancelled:
            statusCard {
                Image(systemName: "pause.circle")
                Text("Request cancelled")
            }
        case .error(let message):
            statusCard {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .idle, .prompting:
            EmptyView()
        }
    }

    private func responseText(_ text: String) -> some View {
        ScrollView(.vertical) {
            Text(text.isEmpty ? " " : text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        }
        .frame(maxHeight: 420)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .accessibilityLabel("Response text")
    }

    private func statusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10, content: content)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var footer: some View {
        switch state {
        case .loading, .streaming:
            HStack {
                Text("You can cancel at any time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Cancel", role: .cancel) { onCancel?() }
                    .buttonStyle(.bordered)
            }
        case .completed:
            HStack {
                Button {
                    onCopy?(visibleResponse)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(visibleResponse.isEmpty)
                .accessibilityHint("Copy the response to the clipboard")
                Spacer(minLength: 8)
                escButton
            }
        case .cancelled, .error:
            HStack {
                Button("Try Again", action: { onRetry?() })
                    .buttonStyle(.borderedProminent)
                    .disabled(onRetry == nil)
                Spacer(minLength: 8)
                escButton
            }
        case .idle, .prompting:
            EmptyView()
        }
    }

    private var escButton: some View {
        Button {
            onCancel?()
        } label: {
            Label("Press Esc to close", systemImage: "escape")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(.escape)
        .foregroundStyle(.secondary)
    }
}
