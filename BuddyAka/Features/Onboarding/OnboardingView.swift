import SwiftUI

struct OnboardingView: View {
    var body: some View {
        ScrollView {
            PermissionsList(filter: .all)
                .padding()
        }
    }
}
