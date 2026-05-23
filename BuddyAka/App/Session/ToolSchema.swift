import BuddyVoice
import Foundation

enum BuddyTools {
    static let getUITree = FunctionDeclaration(
        name: "get_ui_tree",
        description: "Capture the normalized UI tree of the frontmost app's focused window. Native apps are grounded through macOS Accessibility; supported browser pages may be grounded through DOM when Accessibility is sparse. Returns a compact list of interactable elements, each with an opaque session-local id you can pass to point_to_element, plus the app bundle id, window title, and page URL when available. Call this before point_to_element, and call it again whenever the screen has changed.",
        parameters: Schema(
            type: .object,
            properties: [
                "focused_window_only": Schema(
                    type: .boolean,
                    description: "If true (default), only the frontmost window's elements are returned. Set false to scan the whole app tree (slower)."
                )
            ]
        )
    )

    static let pointToElement = FunctionDeclaration(
        name: "point_to_element",
        description: "MANDATORY for showing the user anything on screen. The user CANNOT see UI elements you describe in words — only the buddy cursor and halo this tool draws. Call this every time you mention a specific button, link, field, menu item, or other element. Moves the buddy cursor to the element with the given session id and pulses a halo around it. Then speak one short sentence describing what you pointed at, in the user's language.",
        parameters: Schema(
            type: .object,
            properties: [
                "element_id": Schema(
                    type: .string,
                    description: "An opaque id from the most recent get_ui_tree response."
                ),
                "narration": Schema(
                    type: .string,
                    description: "Optional. Not played by the client — speak the narration aloud via your voice modality."
                )
            ],
            required: ["element_id"]
        )
    )

    static let startTour = FunctionDeclaration(
        name: "start_tour",
        description: "Begin Tour Mode: a guided walk through the current screen where the app moves the halo from one element to the next on its own and you narrate each. Call this only after `get_ui_tree` and only when the user asked to be shown the screen (e.g. \"walk me through\", \"explain this screen\"). Provide 5–8 (max 12) element_ids in scan order. The app pins the current UI snapshot, points the halo at the first element, and returns its label and role. Narrate that first element in ONE short sentence and then WAIT — do not call any more tools. The app will tick the halo forward and send `[BUDDY_EVENT] {\"type\":\"tour_step\", ...}` for each subsequent element.",
        parameters: Schema(
            type: .object,
            properties: [
                "element_ids": Schema(
                    type: .array,
                    description: "Ids from the most recent get_ui_tree response, in the order you want the user to see them.",
                    items: Schema(type: .string)
                )
            ],
            required: ["element_ids"]
        )
    )

    static let stopTour = FunctionDeclaration(
        name: "stop_tour",
        description: "End the active tour. Use when the user says \"stop\", \"хватит\", \"bo'ldi\", etc., or when you're handing control back. Returns success and the app hides the halo.",
        parameters: Schema(type: .object)
    )

    static let resumeTour = FunctionDeclaration(
        name: "resume_tour",
        description: "Resume a paused tour after a user interruption side-conversation. Call ONLY after the user has confirmed they want to keep going. The app advances the halo to the next element and emits the next `[BUDDY_EVENT]` tour_step event (or tour_complete if you were on the last step).",
        parameters: Schema(type: .object)
    )

    static let all: [Tool] = [
        Tool(functionDeclarations: [getUITree, pointToElement, startTour, stopTour, resumeTour])
    ]
}

struct GetUITreeArgs: Decodable {
    var focused_window_only: Bool?
}

struct PointToElementArgs: Decodable {
    let element_id: String
}

struct StartTourArgs: Decodable {
    let element_ids: [String]
}
