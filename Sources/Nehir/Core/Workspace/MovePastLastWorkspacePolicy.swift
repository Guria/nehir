// SPDX-FileCopyrightText: 2026 BarutSRB
// SPDX-FileCopyrightText: 2026 Aleksei Gurianov and Nehir contributors
// SPDX-FileComment: Provenance=upstream-derived; Upstream-Project=OmniWM; Upstream-Author=BarutSRB; Nehir-Changes-Since=2026; See=NOTICE.md
//
// SPDX-License-Identifier: GPL-2.0-only

import Foundation

/// What "move the focused window one workspace further" does when there is no
/// further workspace in that direction on the monitor.
///
/// This governs only the end-of-list edge reached by moving *down* (toward
/// higher-numbered workspaces). Moving *up* past the first workspace always
/// wraps: workspaces are numbered from 1, so there is no lower-numbered
/// workspace to create, and refusing to move would leave the keystroke with no
/// effect at all.
///
/// Workspace *switching* is deliberately not governed by this policy — it has
/// always wrapped in both directions and never created workspaces.
enum MovePastLastWorkspacePolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Create the next numbered workspace and move the window into it.
    case create
    /// Wrap around to the first workspace on the monitor.
    case wrap

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .create: "Create New Workspace"
        case .wrap: "Wrap to First Workspace"
        }
    }
}
