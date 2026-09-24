import SwiftUI

/// One duplicate-contact group: the contacts, why they matched, the merged result, and
/// the actions that add to the cart (FR-CON-2/3).
struct ContactGroupCard: View {
    let group: DuplicateContactGroup
    let primaryID: String
    let selectedForDeletion: Set<String>
    let mergeQueued: Bool
    let onSetPrimary: (String) -> Void
    let onToggleDelete: (String) -> Void
    let onToggleMerge: () -> Void

    private var merged: ContactSummary { group.mergedPreview(primaryID: primaryID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            reasons
            VStack(spacing: 0) {
                ForEach(Array(group.contacts.enumerated()), id: \.element.id) { index, contact in
                    contactRow(contact)
                    if index < group.contacts.count - 1 { Divider().overlay(Color.sift.hairline) }
                }
            }
            .background(Color.sift.canvas, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

            mergedPreview
            actions
        }
        .padding(Spacing.m)
        .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(mergeQueued ? Color.sift.accent : Color.sift.hairline, lineWidth: mergeQueued ? 1.5 : 1))
        .animation(Motion.standard, value: mergeQueued)
        .animation(Motion.standard, value: primaryID)
    }

    private var reasons: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(group.reasons, id: \.self) { reason in
                Label(reason.label, systemImage: reason.symbol)
                    .font(Font.sift.badge)
                    .foregroundStyle(Color.sift.catContacts)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 4)
                    .background(Color.sift.catContacts.opacity(0.14), in: Capsule())
            }
            Spacer()
            Text("^[\(group.contacts.count) contact](inflect: true)")
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.inkSecondary)
        }
    }

    private func contactRow(_ contact: ContactSummary) -> some View {
        let isPrimary = contact.id == primaryID
        let isDeleting = selectedForDeletion.contains(contact.id)
        return HStack(spacing: Spacing.s) {
            Button { onSetPrimary(contact.id) } label: {
                Image(systemName: isPrimary ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isPrimary ? Color.sift.accent : Color.sift.inkTertiary)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .buttonStyle(.plain)
            .disabled(mergeQueued)
            .accessibilityLabel(Text(isPrimary ? "Primary contact" : "Make primary"))

            ContactAvatar(contact: contact, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(contact.displayName)
                        .font(Font.sift.headline)
                        .foregroundStyle(isDeleting ? Color.sift.inkTertiary : Color.sift.inkPrimary)
                        .strikethrough(isDeleting)
                    if isPrimary {
                        Text("Keep")
                            .font(Font.sift.badge)
                            .foregroundStyle(Color.sift.onAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.sift.accent, in: Capsule())
                    }
                }
                ForEach(contact.phones + contact.emails, id: \.self) { line in
                    Text(line)
                        .font(Font.sift.caption)
                        .foregroundStyle(Color.sift.inkSecondary)
                        .lineLimit(1)
                }
                if !contact.organization.isEmpty {
                    Text(contact.organization).font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
                }
            }
            Spacer(minLength: Spacing.xs)

            Button { onToggleDelete(contact.id) } label: {
                Image(systemName: isDeleting ? "trash.circle.fill" : "trash.circle")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isDeleting ? Color.sift.onAccent : Color.sift.inkTertiary,
                                     isDeleting ? Color.sift.accent : .clear)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
            }
            .buttonStyle(.plain)
            .disabled(mergeQueued || isPrimary)
            .opacity(mergeQueued || isPrimary ? 0.35 : 1)
            .accessibilityLabel(Text(isDeleting ? "Don't delete" : "Delete this contact"))
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.xxs)
        .sensoryFeedback(.selection, trigger: isDeleting)
    }

    private var mergedPreview: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "arrow.triangle.merge")
                .foregroundStyle(Color.sift.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Merged result")
                    .font(Font.sift.badge)
                    .foregroundStyle(Color.sift.inkSecondary)
                    .textCase(.uppercase)
                Text(merged.displayName)
                    .font(Font.sift.headline)
                    .foregroundStyle(Color.sift.inkPrimary)
                Text((merged.phones + merged.emails).joined(separator: " · "))
                    .font(Font.sift.caption)
                    .foregroundStyle(Color.sift.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sift.accentSoft, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: Spacing.xs) {
            Button(action: onToggleMerge) {
                Label(mergeQueued ? "Merge queued" : "Merge into one", systemImage: mergeQueued ? "checkmark" : "arrow.triangle.merge")
                    .font(Font.sift.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(mergeQueued ? Color.sift.onAccent : Color.sift.accent)
                    .background(mergeQueued ? Color.sift.accent : Color.sift.accentSoft, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .sensoryFeedback(.selection, trigger: mergeQueued)
        }
    }
}

#Preview {
    ScrollView {
        ContactGroupCard(
            group: DuplicateContactGroup(id: UUID(), contacts: [
                ContactSummary(id: "1", givenName: "Priya", familyName: "Raman", organization: "", phones: ["+91 98400 12345"], emails: ["priya.r@example.test"], hasImage: true),
                ContactSummary(id: "2", givenName: "Priya", familyName: "Raman", organization: "Meridian Labs", phones: ["+91 98400 12345", "+91 44 2811 0099"], emails: [], hasImage: false),
            ], reasons: [.samePhone, .sameName]),
            primaryID: "1", selectedForDeletion: ["2"], mergeQueued: false,
            onSetPrimary: { _ in }, onToggleDelete: { _ in }, onToggleMerge: {}
        )
        .padding()
    }
    .background(Color.sift.canvas)
}
