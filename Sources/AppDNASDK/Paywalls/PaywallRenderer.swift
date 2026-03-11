import SwiftUI

/// Schema-driven SwiftUI view that renders a PaywallConfig.
struct PaywallRenderer: View {
    let config: PaywallConfig
    let onPlanSelected: (PaywallPlan) -> Void
    let onRestore: () -> Void
    let onDismiss: (DismissReason) -> Void

    @State private var selectedPlanId: String?
    @State private var showDismiss = false
    @State private var isPurchasing = false

    // SPEC-084: Localization helper
    private func loc(_ key: String, _ fallback: String) -> String {
        LocalizationEngine.resolve(key: key, localizations: config.localizations, defaultLocale: config.default_locale, fallback: fallback)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundView

            ScrollView {
                VStack(spacing: config.layout.spacing ?? 16) {
                    ForEach(Array(config.sections.enumerated()), id: \.offset) { _, section in
                        sectionView(for: section)
                    }
                }
                .padding(config.layout.padding ?? 20)
            }

            // Dismiss control
            if showDismiss {
                let dismissType = config.dismiss?.type ?? "x_button"
                switch dismissType {
                case "text_link":
                    VStack {
                        Spacer()
                        Button {
                            onDismiss(.dismissed)
                        } label: {
                            Text(config.dismiss?.text ?? "No thanks")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.bottom, 24)
                    }
                default: // x_button
                    dismissButton
                }
            }
        }
        .entryAnimation(config.animation?.entry_animation, durationMs: config.animation?.entry_duration_ms)
        .onAppear {
            // Select default plan
            if let sections = config.sections.first(where: { $0.type == "plans" }),
               let plans = sections.data?.plans {
                selectedPlanId = plans.first(where: { $0.isDefault == true })?.id ?? plans.first?.id
            }

            // Handle dismiss delay
            let delay = config.dismiss?.delaySeconds ?? 0
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) {
                    withAnimation { showDismiss = true }
                }
            } else {
                showDismiss = true
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundView: some View {
        switch config.background?.type {
        case "gradient":
            if let colors = config.background?.colors, colors.count >= 2 {
                LinearGradient(
                    colors: colors.map { Color(hex: $0) },
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        case "image":
            if let urlString = config.background?.value, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        case "color":
            Color(hex: config.background?.value ?? "#000000")
                .ignoresSafeArea()
        default:
            Color(.systemBackground).ignoresSafeArea()
        }
    }

    // MARK: - Dismiss button

    private var dismissButton: some View {
        Button {
            onDismiss(.dismissed)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
        }
        .padding(16)
        .transition(.opacity)
    }

    // MARK: - Section rendering

    @ViewBuilder
    private func sectionView(for section: PaywallSection) -> some View {
        let staggerDelay = config.animation?.section_stagger_delay_ms ?? 0

        Group {
            switch section.type {
            case "header":
                HeaderSection(data: section.data, loc: loc)
                    .applyContainerStyle(section.style?.container)
            case "features":
                FeatureList(features: section.data?.features ?? [])
                    .applyContainerStyle(section.style?.container)
            case "plans":
                plansSection(plans: section.data?.plans ?? [])
                    .applyContainerStyle(section.style?.container)
            case "cta":
                CTAButton(
                    cta: section.data?.cta,
                    isPurchasing: isPurchasing,
                    onTap: handleCTATap
                )
                .ctaAnimation(config.animation?.cta_animation)
                .applyContainerStyle(section.style?.container)
            case "social_proof":
                socialProofSection(data: section.data)
                    .applyContainerStyle(section.style?.container)
            case "guarantee":
                if let text = section.data?.guaranteeText {
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            // SPEC-084: Missing sections
            case "image":
                imageSectionView(data: section.data, style: section.style)
            case "spacer":
                Spacer().frame(height: section.data?.spacerHeight ?? 24)
            case "testimonial":
                testimonialSectionView(data: section.data, style: section.style)
            default:
                EmptyView()
            }
        }
        .sectionStagger(config.animation?.section_stagger, delayMs: staggerDelay)
    }

    // MARK: - SPEC-084: Social proof with sub-types

    @ViewBuilder
    private func socialProofSection(data: PaywallSectionData?) -> some View {
        switch data?.subType {
        case "countdown":
            CountdownTimerView(seconds: data?.countdownSeconds ?? 86400)
        case "trial_badge":
            Text(data?.text ?? "Free Trial")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .clipShape(Capsule())
        default: // app_rating
            SocialProof(data: data)
        }
    }

    // MARK: - SPEC-084: Image section

    @ViewBuilder
    private func imageSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        if let urlString = data?.imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: data?.height ?? 240)
                        .clipShape(RoundedRectangle(cornerRadius: data?.cornerRadius ?? 12))
                default:
                    ProgressView().frame(height: data?.height ?? 240)
                }
            }
            .applyContainerStyle(style?.container)
        }
    }

    // MARK: - SPEC-084: Testimonial section

    private func testimonialSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        VStack(spacing: 12) {
            Text("\u{201C}")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.accentColor)

            Text(loc("testimonial.quote", data?.quote ?? data?.testimonial ?? ""))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.9))

            HStack(spacing: 12) {
                if let avatarUrl = data?.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else if let name = data?.authorName {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(initials(name))
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let name = data?.authorName {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    if let role = data?.authorRole {
                        Text(role)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .applyContainerStyle(style?.container)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first.map { String($0.prefix(1)) } ?? ""
        let last = parts.count > 1 ? String(parts.last!.prefix(1)) : ""
        return (first + last).uppercased()
    }

    // MARK: - Plans

    // SPEC-084: Grid/carousel/stack plan layouts
    @ViewBuilder
    private func plansSection(plans: [PaywallPlan]) -> some View {
        let layoutType = config.layout.type

        VStack(spacing: 12) {
            switch layoutType {
            case "grid":
                // Side-by-side plan cards
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(plans) { plan in
                        PlanCard(
                            plan: plan,
                            isSelected: selectedPlanId == plan.id,
                            onSelect: { selectedPlanId = plan.id }
                        )
                        .planSelection(config.animation?.plan_selection_animation, isSelected: selectedPlanId == plan.id)
                    }
                }

            case "carousel":
                // Swipeable horizontal plan cards
                TabView {
                    ForEach(plans) { plan in
                        PlanCard(
                            plan: plan,
                            isSelected: selectedPlanId == plan.id,
                            onSelect: { selectedPlanId = plan.id }
                        )
                        .planSelection(config.animation?.plan_selection_animation, isSelected: selectedPlanId == plan.id)
                        .padding(.horizontal, 8)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 140)

            default: // "stack"
                ForEach(plans) { plan in
                    PlanCard(
                        plan: plan,
                        isSelected: selectedPlanId == plan.id,
                        onSelect: { selectedPlanId = plan.id }
                    )
                    .planSelection(config.animation?.plan_selection_animation, isSelected: selectedPlanId == plan.id)
                }
            }

            Button(loc("restore.text", "Restore Purchases")) {
                onRestore()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - CTA handler

    private func handleCTATap() {
        guard let planId = selectedPlanId,
              let section = config.sections.first(where: { $0.type == "plans" }),
              let plan = section.data?.plans?.first(where: { $0.id == planId }) else {
            return
        }
        isPurchasing = true
        onPlanSelected(plan)
    }
}

// MARK: - Countdown timer (SPEC-084 social proof sub-type)

struct CountdownTimerView: View {
    let seconds: Int
    @State private var remaining: Int

    init(seconds: Int) {
        self.seconds = seconds
        self._remaining = State(initialValue: seconds)
    }

    var body: some View {
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let secs = remaining % 60

        HStack(spacing: 4) {
            timeUnit(hours, label: "h")
            Text(":").foregroundColor(.white.opacity(0.6))
            timeUnit(minutes, label: "m")
            Text(":").foregroundColor(.white.opacity(0.6))
            timeUnit(secs, label: "s")
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                if remaining > 0 {
                    remaining -= 1
                } else {
                    timer.invalidate()
                }
            }
        }
    }

    private func timeUnit(_ value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", value))
                .font(.title2.monospacedDigit().bold())
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(minWidth: 40)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
