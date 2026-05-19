import SwiftUI

struct MutedKeywordsView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var keywords: [String] = []
    @State private var newKeyword: String = ""
    @FocusState private var keywordFieldFocused: Bool

    var body: some View {
        List {
            Section(header: Text("Add New Keyword")) {
                HStack {
                    TextField("Enter keyword or phrase", text: $newKeyword)
                        .focused($keywordFieldFocused)
                        .onSubmit(addKeyword)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)

                    Button(action: addKeyword) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add muted keyword")
                }
            }

            Section(header: Text("Muted Keywords"), footer: Text("Posts containing these keywords will be hidden from your timeline. Matching is case-insensitive.")) {
                if keywords.isEmpty {
                    Text("No muted keywords")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(keywords, id: \.self) { keyword in
                        Text(keyword)
                    }
                    .onDelete(perform: removeKeywords)
                }
            }
        }
        .navigationTitle("Muted Keywords")
        .onAppear {
            keywords = serviceManager.currentBlockedKeywords
        }
    }

    private func addKeyword() {
        let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // The filter compares lowercased content against lowercased
        // keywords (SocialModels.swift), so "Trump" and "trump" filter
        // the same posts — dedup case-insensitively here too so the
        // user-facing list doesn't show what look like duplicates that
        // are actually equivalent at filter time.
        let alreadyPresent = keywords.contains {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if alreadyPresent {
            HapticEngine.warning.trigger()
            newKeyword = ""
            keywordFieldFocused = true
            return
        }

        keywords.append(trimmed)
        serviceManager.updateBlockedKeywords(keywords)
        HapticEngine.selection.trigger()
        newKeyword = ""
        // Keep the field focused so the user can chain additions
        // without re-tapping (matches the iOS Reminders quick-add flow).
        keywordFieldFocused = true
    }

    private func removeKeywords(at offsets: IndexSet) {
        keywords.remove(atOffsets: offsets)
        serviceManager.updateBlockedKeywords(keywords)
    }
}

