import SwiftUI

/// A workbook, read and not yet applied (Plan IH §6).
///
/// Everything the import would do is on this sheet before anything is written: counts, new lines,
/// changed details, lines the sheet no longer has, and rows that were refused. One button applies
/// all of it as a single batch, so one Undo on the Van Stock screen takes it back.
struct VanStockImportReviewSheet: View {
    @ObservedObject var service: VanStockImportService
    /// Called after the import was applied.
    let onApplied: () -> Void

    /// Lines that moved on the phone after the workbook was written, where the technician chose
    /// to keep the phone's figure. The sheet's figure is the default.
    @State private var keepingPhoneFigure: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                switch service.stage {
                case .idle:
                    EmptyView()
                case .refused(let refusal):
                    refusedView(refusal)
                case .reviewing(let proposal, let fileName):
                    reviewList(proposal, fileName: fileName)
                }
            }
            .navigationTitle("Spreadsheet import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { service.dismiss() }
                }
                if case .reviewing(let proposal, _) = service.stage {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            if service.apply(keepingPhoneFigure: keepingPhoneFigure) { onApplied() }
                        }
                        .disabled(proposal.changesNothing)
                    }
                }
            }
        }
    }

    // MARK: - Refused

    private func refusedView(_ refusal: VanStockImportService.Refusal) -> some View {
        List {
            Section {
                Label {
                    refusalText(refusal)
                } icon: {
                    Image(systemName: refusal == .nothingToChange ? "checkmark.circle" : "exclamationmark.triangle")
                }
            } footer: {
                Text("Nothing on the van list was changed.")
            }
        }
        .ogFormStyle()
    }

    private func refusalText(_ refusal: VanStockImportService.Refusal) -> Text {
        switch refusal {
        case .fieldAssistOff:
            return Text("Field Assist is off, so there is no van list to import into.")
        case .switchedOffByOrganisation:
            return Text("Your organisation has switched van stock off on this phone.")
        case .listUnreadable:
            return Text("The van list on this phone can't be read. Start it again from the Van stock screen first.")
        case .fileUnreadable:
            return Text("That file couldn't be read.")
        case .workbook(.notAWorkbook):
            return Text("That isn't a spreadsheet this can read. Save it as an Excel workbook (.xlsx) with no password.")
        case .workbook(.tooLarge):
            return Text("That spreadsheet is too large to import.")
        case .workbook(.macros):
            return Text("That spreadsheet contains macros, so it wasn't opened. Save it as an ordinary workbook (.xlsx).")
        case .workbook(.tooManyRows):
            return Text("That spreadsheet has more than 5,000 rows.")
        case .noRecognisableHeader:
            return Text("That spreadsheet has no header row this recognises. It needs Part number or Description, and On hand.")
        case .nothingToChange:
            return Text("That spreadsheet matches the van list already. There is nothing to import.")
        }
    }

    // MARK: - Review

    @ViewBuilder
    private func reviewList(_ proposal: VanStockSheet.Proposal, fileName: String) -> some View {
        List {
            Section {
                Text(fileName)
                    .font(.headline)
                Text("\(proposal.counts.count) counts, \(proposal.newLines.count) new lines, \(proposal.edits.count) lines with changed details.")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Nothing is changed until you tap Apply. Undo on the Van stock screen takes the whole import back.")
            }

            let conflicts = proposal.counts.filter(\.movedSinceExport)
            if !conflicts.isEmpty {
                Section {
                    ForEach(conflicts) { count in
                        Toggle(isOn: Binding(
                            get: { keepingPhoneFigure.contains(count.itemID) },
                            set: { keep in
                                if keep { keepingPhoneFigure.insert(count.itemID) } else { keepingPhoneFigure.remove(count.itemID) }
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(count.name)
                                Text("Spreadsheet says \(count.to). The phone says \(count.from ?? 0).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Changed on the phone since the spreadsheet was made")
                } footer: {
                    Text("The spreadsheet's figure is used unless you switch a line on to keep the phone's.")
                }
            }

            let plain = proposal.counts.filter { !$0.movedSinceExport }
            if !plain.isEmpty {
                Section {
                    ForEach(plain) { count in
                        LabeledContent(count.name) {
                            if let from = count.from {
                                Text("\(from) → \(count.to)")
                            } else {
                                Text("\(count.to)")
                            }
                        }
                    }
                } header: {
                    Text("Counts")
                }
            }

            if !proposal.newLines.isEmpty {
                Section {
                    ForEach(proposal.newLines) { line in
                        LabeledContent(line.description.isEmpty ? (line.number ?? "") : line.description) {
                            if let onHand = line.onHand {
                                Text("\(onHand)")
                            } else {
                                Text("Not counted")
                            }
                        }
                    }
                } header: {
                    Text("New lines")
                }
            }

            if !proposal.edits.isEmpty {
                Section {
                    ForEach(proposal.edits) { edit in
                        LabeledContent(edit.name) { Text("\(edit.changes.count) changes") }
                    }
                } header: {
                    Text("Changed details")
                }
            }

            if !proposal.missing.isEmpty {
                Section {
                    ForEach(proposal.missing) { item in Text(item.name) }
                } header: {
                    Text("Not in the spreadsheet")
                } footer: {
                    Text("These stay exactly as they are. To clear a line, set its count to zero.")
                }
            }

            if !proposal.refusals.isEmpty {
                Section {
                    ForEach(proposal.refusals) { refusal in
                        LabeledContent {
                            reasonText(refusal.reason)
                        } label: {
                            Text("Row \(refusal.row)")
                        }
                    }
                } header: {
                    Text("Rows left out")
                } footer: {
                    Text("Fix these in the spreadsheet and import it again, or change the lines here.")
                }
            }
        }
        .ogFormStyle()
    }

    private func reasonText(_ reason: VanStockSheet.Proposal.Refusal.Reason) -> Text {
        switch reason {
        case .notAWholeNumber(let column, let value):
            return Text("\(column) “\(value)” isn't a whole number")
        case .unknownUnit(let unit):
            return Text("“\(unit)” isn't a unit the list keeps")
        case .noPartNumberOrDescription:
            return Text("No part number or description")
        case .repeatsRow(let row):
            return Text("Repeats row \(row)")
        }
    }
}
