import Testing
@testable import CubbyCore

struct OnboardingStepTests {
    @Test func stepsAreInWizardOrder() {
        #expect(OnboardingStep.allCases == [.welcome, .permissions, .style, .shortcut])
        #expect(OnboardingStep.allCases.map(\.number) == [1, 2, 3, 4])
    }

    @Test func nextAndPreviousStopAtTheEnds() {
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.welcome.next == .permissions)
        #expect(OnboardingStep.style.previous == .permissions)
        #expect(OnboardingStep.style.next == .shortcut)
        #expect(OnboardingStep.shortcut.next == nil)
    }

    @Test func firstAndLast() {
        #expect(OnboardingStep.welcome.isFirst)
        #expect(!OnboardingStep.welcome.isLast)
        #expect(OnboardingStep.shortcut.isLast)
        #expect(!OnboardingStep.shortcut.isFirst)
        #expect(!OnboardingStep.style.isFirst && !OnboardingStep.style.isLast)
    }

    @Test func progressRelativeToCurrentStep() {
        let progress = OnboardingStep.allCases.map { $0.progress(current: .style) }
        #expect(progress == [.done, .done, .current, .upcoming])
        #expect(OnboardingStep.welcome.progress(current: .welcome) == .current)
        #expect(OnboardingStep.shortcut.progress(current: .welcome) == .upcoming)
    }

    @Test func layoutPositionKeepsTheFloatingChoice() {
        #expect(PanelLayout.floating.position(floatingFallback: .statusItem) == .statusItem)
        #expect(PanelLayout.floating.position(floatingFallback: .center) == .center)
        #expect(PanelLayout.floating.position(floatingFallback: .mouse) == .mouse)
        #expect(PanelLayout.floating.position(floatingFallback: .dockRight) == .mouse)
        #expect(PanelLayout.sidebar.position(floatingFallback: .center) == .dockRight)
        #expect(PanelLayout.shelf.position(floatingFallback: .center) == .dockBottom)
    }
}
