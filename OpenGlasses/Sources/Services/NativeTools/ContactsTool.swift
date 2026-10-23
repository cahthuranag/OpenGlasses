import Foundation
import Contacts

/// Looks up contacts by name and returns phone numbers, email addresses.
/// Enables phone_call and send_message to work by name ("call Mom").
final class ContactsTool: NativeTool, @unchecked Sendable {
    let name = "lookup_contact"
    let description = "Look up a contact by name to get their phone number or email. Useful before making a call or sending a message by name."
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": [
                "type": "string",
                "description": "The contact name to search for, e.g. 'Mom', 'John Smith', 'Dr. Chen'"
            ]
        ],
        "required": ["name"]
    ]

    private let store = CNContactStore()

    func execute(args: [String: Any]) async throws -> String {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return "No contact name provided."
        }

        // Request access
        let granted: Bool
        if #available(iOS 18.0, *) {
            granted = try await store.requestAccess(for: .contacts)
        } else {
            granted = try await store.requestAccess(for: .contacts)
        }

        guard granted else {
            return "Contacts access denied. Please enable it in iPhone Settings > Privacy & Security > Contacts."
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]

        let predicate = CNContact.predicateForContacts(matchingName: name)

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

            guard !contacts.isEmpty else {
                return "No contacts found matching '\(name)'."
            }

            var results: [String] = []
            for contact in contacts.prefix(5) {
                let fullName = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let displayName = fullName.isEmpty ? (contact.organizationName.isEmpty ? "Unknown" : contact.organizationName) : fullName

                var info = displayName

                // Phone numbers
                let phones = contact.phoneNumbers.map { phone -> String in
                    let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? "")
                    let number = phone.value.stringValue
                    return label.isEmpty ? number : "\(label): \(number)"
                }
                if !phones.isEmpty {
                    info += " — \(phones.joined(separator: ", "))"
                }

                // Email
                let emails = contact.emailAddresses.map { $0.value as String }
                if !emails.isEmpty && phones.isEmpty {
                    info += " — \(emails.first!)"
                }

                results.append(info)
            }

            var response = results.joined(separator: ". ")
            if contacts.count > 5 {
                response += ". Plus \(contacts.count - 5) more matches."
            }
            return response
        } catch {
            return "Couldn't search contacts: \(error.localizedDescription)"
        }
    }
}
