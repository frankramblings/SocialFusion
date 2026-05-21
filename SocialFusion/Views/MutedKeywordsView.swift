import SwiftUI

struct MutedKeywordsView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keywords: [String] = []
    @State private var newKeyword: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("Enter keyword or phrase", text: $newKeyword)
                        .submitLabel(.done)
                        .focused($isInputFocused)
                        .onSubmit(addKeyword)
                        .autocorrectionDisabled()

                    Button(action: addKeyword) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(canAdd ? Color.accentColor : Color.secondary.opacity(0.4))
                            .symbolRenderingMode(.hierarchical)
                            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: canAdd)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .accessibilityLabel("Add muted keyword")
                }
            } header: {
                Text("Add New Keyword")
            } footer: {
                Text("Hide posts containing specific words or phrases from your timeline.")
            }

            Section {
                if keywords.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(keywords, id: \.self) { keyword in
                        HStack(spacing: 10) {
                            Image(systemName: "tag.fill")
                                .font(.caption)
                                .foregroundStyle(Color.orange.gradient)
                                .symbolRenderingMode(.hierarchical)
                                .accessibilityHidden(true)

                            Text(keyword)
                                .font(.body)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Muted keyword: \(keyword)")
                    }
                    .onDelete(perform: removeKeywords)
                }
            } header: {
                Text("Muted Keywords")
            } footer: {
                if !keywords.isEmpty {
                    Text("Swipe left on a keyword to remove it.")
                }
            }
        }
        .navigationTitle("Muted Keywords")
        // Drop the keyboard when the user scrolls the list — same
        // convention as the search lists.
        .scrollDismissesKeyboard(.immediately)
        .onAppear {
            keywords = serviceManager.currentBlockedKeywords
        }
    }

    private var canAdd: Bool {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !keywords.contains(trimmed)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tag.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.secondary.gradient)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 8)

            Text("No muted keywords")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            Text("Add a word or phrase above to hide matching posts.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func addKeyword() {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        HapticEngine.success.trigger()

        if !keywords.contains(trimmed) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                keywords.append(trimmed)
            }
            serviceManager.updateBlockedKeywords(keywords)
        }
        newKeyword = ""
    }

    private func removeKeywords(at offsets: IndexSet) {
        HapticEngine.tap.trigger()
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
            keywords.remove(atOffsets: offsets)
        }
        serviceManager.updateBlockedKeywords(keywords)
    }
}
