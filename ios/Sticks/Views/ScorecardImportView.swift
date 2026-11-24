//
//  ScorecardImportView.swift
//  Sticks
//
//  Full-screen import flow: pick scorecard screenshots (18Birdies,
//  Arccos, a paper card…), let the server read them, review/edit the
//  grid, and save it as a real finished round. Opened from the New
//  round wizard's first step.
//

import PhotosUI
import SwiftUI

struct ScorecardImportView: View {
    let user: User
    let session: SessionStore
    /// Called with the new match id after a successful save.
    let onImported: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ScorecardImportViewModel
    @State private var pickerItems: [PhotosPickerItem] = []
    @FocusState private var focus: ImportFocus?

    init(user: User, session: SessionStore, onImported: @escaping (String) -> Void) {
        self.user = user
        self.session = session
        self.onImported = onImported
        _viewModel = State(initialValue: ScorecardImportViewModel(user: user))
    }

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            switch viewModel.phase {
            case .pick:
                pickView.transition(.opacity)
            case .reading:
                readingView.transition(.opacity)
            case .failed(let message):
                failedView(message).transition(.opacity)
            case .review, .saving:
                reviewView.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: viewModel.phase)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPicked(items) }
        }
        .task { await viewModel.bootstrap(session: session) }
        .interactiveDismissDisabled(viewModel.phase == .saving)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("IMPORT ROUND")
                .font(SticksFont.mono(11))
                .kerning(1.54)
                .foregroundStyle(Color.sticksGreen)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(width: 32, height: 32)
                    .background(Color.sticksPanel2)
                    .clipShape(.circle)
            }
            .disabled(viewModel.phase == .saving)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.sticksBg.opacity(0.97))
    }

    // MARK: - Pick

    private var pickView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bring a round in.")
                        .font(SticksFont.display(34, weight: .bold))
                        .kerning(-0.7)
                        .foregroundStyle(Color.sticksInk)

                    Text("Played with 18Birdies, Arccos or a paper card? Pick a screenshot of the scorecard and Sticks reads the scores for you.")
                        .font(SticksFont.sans(14.5))
                        .foregroundStyle(Color.sticksMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                MiniScorecardArt()

                VStack(alignment: .leading, spacing: 12) {
                    tipRow("rectangle.split.3x1", "Use the hole-by-hole scorecard, not a stats page.")
                    tipRow("square.on.square", "Front and back nine on separate screens? Pick both, up to \(ScorecardImportViewModel.maxImages).")
                    tipRow("pencil", "You'll check every number before anything is saved.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sticksGreen)
                .frame(width: 28, height: 28)
                .background(Color.sticksGreen.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            Text(text)
                .font(SticksFont.sans(14))
                .foregroundStyle(Color.sticksInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    // MARK: - Reading

    private var readingView: some View {
        VStack(spacing: 22) {
            Spacer()
            HStack(spacing: -28) {
                ForEach(Array(viewModel.thumbnails.enumerated()), id: \.offset) { index, image in
                    ScanningThumbnail(image: image)
                        .rotationEffect(.degrees(Double(index - (viewModel.thumbnails.count - 1) / 2) * 6))
                        .zIndex(Double(-index))
                }
            }
            VStack(spacing: 6) {
                Text("Reading your scorecard…")
                    .font(SticksFont.display(22, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
                Text("Pulling holes, pars and every player's scores.")
                    .font(SticksFont.sans(14))
                    .foregroundStyle(Color.sticksMuted)
            }
            .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Failed

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.sticksGold)
                .frame(width: 72, height: 72)
                .background(Color.sticksGold.opacity(0.12))
                .clipShape(.circle)
            Text("Couldn't read that one")
                .font(SticksFont.display(24, weight: .bold))
                .foregroundStyle(Color.sticksInk)
            Text(message)
                .font(SticksFont.sans(14.5))
                .foregroundStyle(Color.sticksMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Review

    private var reviewView: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check the card.")
                        .font(SticksFont.display(34, weight: .bold))
                        .kerning(-0.7)
                        .foregroundStyle(Color.sticksInk)
                    Text(reviewSubtitle)
                        .font(SticksFont.sans(14))
                        .foregroundStyle(Color.sticksMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !viewModel.warnings.isEmpty {
                    warningsCard
                }

                courseSection
                whenSection
                playersSection
                scorecardSection
                    .id("scorecard")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .disabled(viewModel.phase == .saving)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: focus) { _, newFocus in
            switch newFocus {
            case .par, .score:
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("scorecard", anchor: .bottom)
                }
            default:
                break
            }
        }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
                    .font(SticksFont.sans(15, weight: .bold))
                    .foregroundStyle(Color.sticksGreen)
            }
        }
    }

    private var reviewSubtitle: String {
        if viewModel.thumbnails.isEmpty {
            return "Fill in the course, who played and every hole. It saves as a finished round."
        }
        var text = "Read from "
        text += viewModel.sourceLabel ?? (viewModel.thumbnails.count == 1 ? "your screenshot" : "your screenshots")
        text += ". Fix anything that looks off. Highlighted cells are ones Sticks wasn't sure about."
        return text
    }

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.sticksGold)
                        .padding(.top, 2)
                    Text(warning)
                        .font(SticksFont.sans(13.5))
                        .foregroundStyle(Color.sticksInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksGold.opacity(0.12))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sticksGold.opacity(0.35), lineWidth: 1))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.mono(10.5))
            .kerning(1.47)
            .foregroundStyle(Color.sticksGreen)
    }

    // MARK: Course

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("COURSE")

            if let course = viewModel.selectedCourse {
                HStack(spacing: 10) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sticksGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name)
                            .font(SticksFont.display(17))
                            .foregroundStyle(Color.sticksInk)
                            .lineLimit(1)
                        if let city = course.city, !city.isEmpty {
                            Text(city.uppercased())
                                .font(SticksFont.mono(10.5, weight: .regular))
                                .foregroundStyle(Color.sticksMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Button("CHANGE") {
                        viewModel.clearCourse()
                        focus = .course
                    }
                    .font(SticksFont.mono(10.5))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksGreen)
                }
                .padding(.horizontal, 14)
                .frame(height: 56)
                .background(Color.sticksCard)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sticksHairline, lineWidth: 1))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sticksFaint)
                    TextField(
                        "",
                        text: Bindable(viewModel).courseQuery,
                        prompt: Text("Search courses…")
                            .font(SticksFont.sans(15))
                            .foregroundStyle(Color.sticksFaint)
                    )
                    .font(SticksFont.sans(15))
                    .foregroundStyle(Color.sticksInk)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .course)
                    .onChange(of: viewModel.courseQuery) { _, _ in
                        viewModel.searchCourses(session: session)
                    }
                    if viewModel.isSearchingCourses {
                        ProgressView().controlSize(.small).tint(Color.sticksGreen)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color.sticksPanel2)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(focus == .course ? Color.sticksGreen : Color.sticksHairline, lineWidth: 1)
                )

                if !viewModel.courseResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.courseResults.prefix(6).enumerated()), id: \.element.id) { index, course in
                            if index > 0 {
                                Rectangle().fill(Color.sticksHairline).frame(height: 1)
                            }
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    viewModel.selectCourse(course)
                                }
                                focus = nil
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.name)
                                        .font(SticksFont.display(16))
                                        .foregroundStyle(Color.sticksInk)
                                        .lineLimit(1)
                                    Text([course.city, "\(course.holes) HOLES"].compactMap { $0 }.joined(separator: " · ").uppercased())
                                        .font(SticksFont.mono(10.5, weight: .regular))
                                        .foregroundStyle(Color.sticksMuted)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.sticksCard)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sticksHairline, lineWidth: 1))
                }
            }
        }
    }

    // MARK: When + holes

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PLAYED")

            HStack {
                Text("Date & tee time")
                    .font(SticksFont.sans(15))
                    .foregroundStyle(Color.sticksInk)
                Spacer()
                DatePicker(
                    "",
                    selection: Bindable(viewModel).playedAt,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .tint(Color.sticksGreen)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sticksHairline, lineWidth: 1))

            HStack(spacing: 6) {
                ForEach(ImportHoleLayout.allCases) { option in
                    let selected = viewModel.layout == option
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeOut(duration: 0.2)) { viewModel.setLayout(option) }
                    } label: {
                        Text(option.rawValue.uppercased())
                            .font(SticksFont.mono(10.5))
                            .kerning(0.8)
                            .foregroundStyle(selected ? Color.sticksCream : Color.sticksMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(selected ? Color.sticksGreen : Color.sticksPanel2)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Players

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("PLAYERS")
                Spacer()
                Text("TAP ME TO MARK YOUR ROW")
                    .font(SticksFont.mono(9))
                    .kerning(0.9)
                    .foregroundStyle(Color.sticksFaint)
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.seats.enumerated()), id: \.element.id) { index, seat in
                    if index > 0 {
                        Rectangle().fill(Color.sticksHairline).frame(height: 1)
                    }
                    playerRow(seat)
                }
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sticksHairline, lineWidth: 1))

            if viewModel.seats.count < ScorecardImportViewModel.maxSeats {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.2)) { viewModel.addSeat() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("ADD PLAYER")
                            .font(SticksFont.mono(10.5))
                            .kerning(0.8)
                    }
                    .foregroundStyle(Color.sticksGreen)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func playerRow(_ seat: ImportSeat) -> some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeOut(duration: 0.18)) { viewModel.markMe(seat.id) }
            } label: {
                Text("ME")
                    .font(SticksFont.mono(10, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(seat.isMe ? Color.sticksCream : Color.sticksFaint)
                    .frame(width: 36, height: 26)
                    .background(seat.isMe ? Color.sticksGreen : Color.sticksPanel2)
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(seat.isMe ? "This row is you" : "Mark this row as you")

            if seat.isMe {
                Text(user.displayName)
                    .font(SticksFont.sans(15, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("YOUR ACCOUNT")
                    .font(SticksFont.mono(9))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksFaint)
            } else {
                TextField(
                    "",
                    text: nameBinding(seat.id),
                    prompt: Text("Guest name").foregroundStyle(Color.sticksFaint)
                )
                .font(SticksFont.sans(15, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focus, equals: .name(seat.id))
                Text("GUEST")
                    .font(SticksFont.mono(9))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksFaint)
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) { viewModel.removeSeat(seat.id) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.sticksFaint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove player")
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private func nameBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.seats.first(where: { $0.id == id })?.name ?? "" },
            set: { value in
                if let index = viewModel.seats.firstIndex(where: { $0.id == id }) {
                    viewModel.seats[index].name = value
                }
            }
        )
    }

    // MARK: Scorecard grid

    private let nameColumnWidth: CGFloat = 78
    private let cellWidth: CGFloat = 38
    private let rowHeight: CGFloat = 42

    private var scorecardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("SCORECARD")
                Spacer()
                if viewModel.uncertainCount > 0 {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.sticksGold.opacity(0.35))
                            .frame(width: 10, height: 10)
                        Text("\(viewModel.uncertainCount) TO CHECK")
                            .font(SticksFont.mono(9))
                            .kerning(0.8)
                            .foregroundStyle(Color.sticksMuted)
                    }
                }
            }

            HStack(alignment: .top, spacing: 0) {
                // Fixed name column.
                VStack(spacing: 0) {
                    labelCell("HOLE", emphasized: true)
                    labelCell("PAR", emphasized: false)
                    ForEach(viewModel.seats) { seat in
                        labelCell(seat.isMe ? "YOU" : shortName(seat.name), emphasized: seat.isMe)
                    }
                }
                .frame(width: nameColumnWidth)

                ScrollViewReader { columnProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(0 ..< viewModel.holeCount, id: \.self) { column in
                                Text("\(viewModel.holeNumber(at: column))")
                                    .font(SticksFont.mono(11))
                                    .foregroundStyle(Color.sticksCream)
                                    .frame(width: cellWidth, height: rowHeight)
                                    .id("col-\(column)")
                            }
                        }
                        .background(Color.sticksGreen)

                        HStack(spacing: 0) {
                            ForEach(0 ..< viewModel.holeCount, id: \.self) { column in
                                NumberCell(
                                    value: viewModel.pars.indices.contains(column) ? viewModel.pars[column] : nil,
                                    placeholder: "–",
                                    range: 3 ... 6,
                                    style: .par,
                                    isUncertain: false,
                                    isMissing: false,
                                    focus: $focus,
                                    focusKey: .par(column),
                                    onAdvance: { advance(from: .par(column)) }
                                ) { viewModel.setPar($0, column: column) }
                                .frame(width: cellWidth, height: rowHeight)
                            }
                        }
                        .background(Color.sticksPanel2)

                        ForEach(viewModel.seats) { seat in
                            HStack(spacing: 0) {
                                ForEach(0 ..< viewModel.holeCount, id: \.self) { column in
                                    let value = seat.scores.indices.contains(column) ? seat.scores[column] : nil
                                    NumberCell(
                                        value: value,
                                        placeholder: "",
                                        range: 1 ... 15,
                                        style: .score(par: viewModel.pars.indices.contains(column) ? viewModel.pars[column] : nil),
                                        isUncertain: seat.uncertain.contains(column),
                                        isMissing: value == nil,
                                        focus: $focus,
                                        focusKey: .score(seat.id, column),
                                        onAdvance: { advance(from: .score(seat.id, column)) }
                                    ) { viewModel.setScore($0, seat: seat.id, column: column) }
                                    .frame(width: cellWidth, height: rowHeight)
                                }
                            }
                            .overlay(alignment: .top) { Color.sticksHairline.frame(height: 1) }
                        }
                    }
                }
                .onChange(of: focus) { _, newFocus in
                    let column: Int?
                    switch newFocus {
                    case .par(let c): column = c
                    case .score(_, let c): column = c
                    default: column = nil
                    }
                    if let column {
                        withAnimation(.easeOut(duration: 0.2)) {
                            columnProxy.scrollTo("col-\(column)", anchor: .center)
                        }
                    }
                }
                }

                // Fixed totals column.
                VStack(spacing: 0) {
                    totalCell("TOT", header: true)
                    totalCell(viewModel.parTotal.map(String.init) ?? "–", header: false)
                    ForEach(viewModel.seats) { seat in
                        totalCell(String(viewModel.total(for: seat)), header: false, bold: true)
                    }
                }
                .frame(width: 46)
                .background(Color.sticksPanel2)
                .overlay(alignment: .leading) { Color.sticksHairline.frame(width: 1) }
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sticksHairline, lineWidth: 1))

            ForEach(viewModel.seats.filter { seat in
                guard let printed = seat.printedTotal else { return false }
                return seat.scores.allSatisfy { $0 != nil } && printed != viewModel.total(for: seat)
            }) { seat in
                Text("\(seat.isMe ? "Your" : "\(shortName(seat.name))'s") card says \(seat.printedTotal ?? 0), the holes add to \(viewModel.total(for: seat)). Worth a second look.")
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksError)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Tap any number to change it. Unknown pars use the course's when you save.")
                .font(SticksFont.sans(12.5))
                .foregroundStyle(Color.sticksFaint)
        }
    }

    /// Typing a complete number moves on to the next hole, then the
    /// next player's first hole, like filling in a paper card.
    private func advance(from key: ImportFocus) {
        switch key {
        case .par(let column):
            focus = column + 1 < viewModel.holeCount ? .par(column + 1) : nil
        case .score(let seatID, let column):
            if column + 1 < viewModel.holeCount {
                focus = .score(seatID, column + 1)
            } else if let index = viewModel.seats.firstIndex(where: { $0.id == seatID }),
                      index + 1 < viewModel.seats.count {
                focus = .score(viewModel.seats[index + 1].id, 0)
            } else {
                focus = nil
            }
        default:
            focus = nil
        }
    }

    private func labelCell(_ text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(SticksFont.mono(10.5, weight: emphasized ? .bold : .medium))
            .kerning(0.6)
            .foregroundStyle(text == "HOLE" ? Color.sticksCream : (emphasized ? Color.sticksGreen : Color.sticksMuted))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .frame(width: nameColumnWidth, height: rowHeight, alignment: .leading)
            .background(text == "HOLE" ? Color.sticksGreen : (text == "PAR" ? Color.sticksPanel2 : Color.sticksCard))
            .overlay(alignment: .top) {
                if text != "HOLE" && text != "PAR" { Color.sticksHairline.frame(height: 1) }
            }
            .overlay(alignment: .trailing) { Color.sticksHairline.frame(width: 1) }
    }

    private func totalCell(_ text: String, header: Bool, bold: Bool = false) -> some View {
        Text(text)
            .font(SticksFont.mono(header ? 10.5 : 13, weight: bold ? .bold : .medium))
            .foregroundStyle(header ? Color.sticksCream : Color.sticksInk)
            .frame(width: 46, height: rowHeight)
            .background(header ? Color.sticksGreen : Color.clear)
    }

    private func shortName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "GUEST" }
        return (trimmed.split(separator: " ").first.map(String.init) ?? trimmed).uppercased()
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            switch viewModel.phase {
            case .pick:
                photosButton(label: "CHOOSE SCREENSHOTS", icon: "photo.on.rectangle.angled")
                manualButton
            case .reading:
                EmptyView()
            case .failed:
                photosButton(label: "TRY ANOTHER SCREENSHOT", icon: "photo.on.rectangle.angled")
                manualButton
            case .review, .saving:
                if focus == nil || viewModel.phase == .saving {
                    reviewFooter
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.sticksBg.opacity(0.97))
    }

    private func photosButton(label: String, icon: String) -> some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: ScorecardImportViewModel.maxImages,
            selectionBehavior: .ordered,
            matching: .images
        ) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(label)
                    .font(SticksFont.sans(15, weight: .bold))
                    .kerning(0.6)
            }
            .foregroundStyle(Color.sticksCream)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(CreateLedgeButtonStyle(showsLedge: true))
    }

    private var manualButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.startManual()
        } label: {
            Text("ENTER SCORES BY HAND")
                .font(SticksFont.mono(11))
                .kerning(1)
                .foregroundStyle(Color.sticksMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(.plain)
    }

    private var reviewFooter: some View {
        VStack(spacing: 10) {
            if let error = viewModel.saveError {
                Text(error)
                    .font(SticksFont.sans(13))
                    .foregroundStyle(Color.sticksError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if viewModel.phase == .review, let blocker = viewModel.saveBlocker {
                Text(blocker)
                    .font(SticksFont.sans(13))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                if viewModel.phase == .review {
                    Button {
                        viewModel.startOver()
                        pickerItems = []
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.sticksMuted)
                            .frame(width: 52, height: 52)
                            .background(Color.sticksPanel2)
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sticksHairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start over")
                }

                Button {
                    focus = nil
                    Task {
                        if let id = await viewModel.save(session: session) {
                            onImported(id)
                        }
                    }
                } label: {
                    Group {
                        if viewModel.phase == .saving {
                            HStack(spacing: 10) {
                                ProgressView().tint(Color.sticksCream)
                                Text(viewModel.saveStatus.uppercased())
                                    .font(SticksFont.mono(11))
                                    .kerning(0.8)
                                    .monospacedDigit()
                            }
                        } else {
                            Text("SAVE ROUND")
                                .font(SticksFont.sans(15, weight: .bold))
                                .kerning(0.6)
                        }
                    }
                    .foregroundStyle(Color.sticksCream)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(alignment: .leading) {
                        if viewModel.phase == .saving {
                            GeometryReader { proxy in
                                Color.sticksGreenDark
                                    .frame(width: proxy.size.width * viewModel.saveProgress)
                                    .animation(.easeOut(duration: 0.2), value: viewModel.saveProgress)
                            }
                        }
                    }
                }
                .buttonStyle(CreateLedgeButtonStyle(showsLedge: viewModel.canSave))
                .disabled(!viewModel.canSave)
                .opacity(viewModel.canSave || viewModel.phase == .saving ? 1 : 0.5)
            }
        }
    }

    // MARK: - Picking

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        pickerItems = []
        guard !images.isEmpty else {
            viewModel.phase = .failed("Couldn't open that image. Try a different screenshot.")
            return
        }
        await viewModel.read(images: images, session: session)
    }
}

// MARK: - Focus

enum ImportFocus: Hashable {
    case course
    case name(UUID)
    case par(Int)
    case score(UUID, Int)
}

// MARK: - Number cell

/// One tappable grid number. Scores tint by result against par, the
/// way a printed card circles birdies; uncertain reads glow gold and
/// missing ones show a red underline.
private struct NumberCell: View {
    enum Style {
        case par
        case score(par: Int?)
    }

    let value: Int?
    let placeholder: String
    let range: ClosedRange<Int>
    let style: Style
    let isUncertain: Bool
    let isMissing: Bool
    var focus: FocusState<ImportFocus?>.Binding
    let focusKey: ImportFocus
    let onAdvance: () -> Void
    let onChange: (Int?) -> Void

    @State private var text = ""

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.sticksFaint))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(SticksFont.mono(14, weight: .semibold))
            .foregroundStyle(foreground)
            .focused(focus, equals: focusKey)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .overlay(alignment: .bottom) {
                if isMissing && focus.wrappedValue != focusKey {
                    Color.sticksError.opacity(0.55).frame(height: 2).padding(.horizontal, 8).padding(.bottom, 6)
                }
            }
            .overlay {
                if focus.wrappedValue == focusKey {
                    RoundedRectangle(cornerRadius: 6).stroke(Color.sticksGreen, lineWidth: 1.5).padding(3)
                }
            }
            .onAppear { text = value.map(String.init) ?? "" }
            .onChange(of: value) { _, newValue in
                let rendered = newValue.map(String.init) ?? ""
                if rendered != text { text = rendered }
            }
            .onChange(of: text) { _, newText in
                let digits = String(newText.filter(\.isNumber).prefix(2))
                if digits != newText { text = digits; return }
                if digits.isEmpty {
                    if value != nil { onChange(nil) }
                    return
                }
                guard let number = Int(digits), range.contains(number) else {
                    // Typing over a filled cell ("5" then "4" → "54"):
                    // the new digit replaces the old one.
                    if digits.count == 2, let last = digits.last { text = String(last) }
                    return
                }
                if number != value { onChange(number) }
                // "1" could still become 10–15; anything else is complete.
                if focus.wrappedValue == focusKey, digits.count == 2 || number >= 2 {
                    onAdvance()
                }
            }
    }

    private var background: Color {
        if isUncertain { return Color.sticksGold.opacity(0.28) }
        guard case .score(let par) = style, let par, let value else { return .clear }
        switch value - par {
        case ...(-1): return Color.sticksGreen.opacity(0.14)
        case 1: return Color.sticksError.opacity(0.06)
        case 2...: return Color.sticksError.opacity(0.13)
        default: return .clear
        }
    }

    private var foreground: Color {
        guard case .score(let par) = style, let par, let value else { return Color.sticksInk }
        return value < par ? Color.sticksGreen : Color.sticksInk
    }
}

// MARK: - Decorative pieces

/// A little scorecard drawn in the app's own type — the intro's hero.
private struct MiniScorecardArt: View {
    private let holes = Array(1 ... 9)
    private let pars = [4, 4, 3, 5, 4, 4, 3, 5, 4]
    private let scores = [4, 5, 3, 4, 4, 6, 2, 5, 4]
    @State private var revealed = 0

    var body: some View {
        VStack(spacing: 0) {
            row(label: "HOLE", values: holes.map(String.init), header: true)
            row(label: "PAR", values: pars.map(String.init), header: false)
            HStack(spacing: 0) {
                Text("YOU")
                    .font(SticksFont.mono(9.5, weight: .bold))
                    .foregroundStyle(Color.sticksGreen)
                    .frame(width: 44, alignment: .leading)
                ForEach(0 ..< 9, id: \.self) { index in
                    ZStack {
                        if scores[index] < pars[index] {
                            Circle().stroke(Color.sticksGreen, lineWidth: 1.2).frame(width: 22, height: 22)
                        }
                        Text(index < revealed ? "\(scores[index])" : "·")
                            .font(SticksFont.mono(12, weight: .semibold))
                            .foregroundStyle(index < revealed ? Color.sticksInk : Color.sticksFaint)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 34)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sticksHairline, lineWidth: 1))
        .shadow(color: Color.sticksInk.opacity(0.06), radius: 12, y: 6)
        .rotationEffect(.degrees(-1.5))
        .padding(.vertical, 6)
        .task {
            for step in 1 ... 9 {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.snappy(duration: 0.25)) { revealed = step }
            }
        }
        .accessibilityHidden(true)
    }

    private func row(label: String, values: [String], header: Bool) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(SticksFont.mono(9.5, weight: .bold))
                .foregroundStyle(header ? Color.sticksGreen : Color.sticksMuted)
                .frame(width: 44, alignment: .leading)
            ForEach(values.indices, id: \.self) { index in
                Text(values[index])
                    .font(SticksFont.mono(header ? 10 : 11))
                    .foregroundStyle(header ? Color.sticksMuted : Color.sticksInk)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 28)
        .overlay(alignment: .bottom) { Color.sticksHairline.frame(height: 1) }
    }
}

/// A picked screenshot with a green scan line sweeping over it.
private struct ScanningThumbnail: View {
    let image: UIImage
    @State private var sweep = false

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 110, height: 200)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [Color.sticksGreen.opacity(0), Color.sticksGreen.opacity(0.45), Color.sticksGreen.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 46)
                    .offset(y: sweep ? proxy.size.height - 23 : -23)
                }
                .clipShape(.rect(cornerRadius: 14))
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sticksHairline, lineWidth: 1))
            .shadow(color: Color.sticksInk.opacity(0.12), radius: 10, y: 5)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    sweep = true
                }
            }
    }
}
