import SwiftUI

struct PermissionsList: View {
    @Environment(PermissionsCoordinator.self) private var permissions
    let filter: Filter

    enum Filter {
        case all
        case missingOnly
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(permissions.rows(filter: filter)) { row in
                PermissionRow(
                    title: row.title,
                    subtitle: row.subtitle,
                    status: row.status,
                    systemSettingsURL: row.url,
                    grant: row.grant
                )
            }
        }
    }
}
