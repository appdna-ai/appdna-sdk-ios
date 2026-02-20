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
                dismissButton
            }
        }
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
        switch section.type {
        case "header":
            HeaderSection(data: section.data)
        case "features":
            FeatureList(features: section.data?.features ?? [])
        case "plans":
            plansSection(plans: section.data?.plans ?? [])
        case "cta":
            CTAButton(
                cta: section.data?.cta,
                isPurchasing: isPurchasing,
                onTap: handleCTATap
            )
        case "social_proof":
            SocialProof(data: section.data)
        case "guarantee":
            if let text = section.data?.guaranteeText {
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Plans

    private func plansSection(plans: [PaywallPlan]) -> some View {
        VStack(spacing: 12) {
            ForEach(plans) { plan in
                PlanCard(
                    plan: plan,
                    isSelected: selectedPlanId == plan.id,
                    onSelect: { selectedPlanId = plan.id }
                )
            }

            Button("Restore Purchases") {
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
