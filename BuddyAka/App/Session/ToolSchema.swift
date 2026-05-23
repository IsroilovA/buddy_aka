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

    static let exitLesson = FunctionDeclaration(
        name: "exit_lesson",
        description: "Drop out of the current lesson while keeping the session alive. Use when the user says they want to stop the lesson, skip it, do something else, or asks a question clearly outside the lesson's scope. After calling, you return to the normal free-form pointing loop and can help with anything else. Returns no_active_lesson if no lesson is running — in that case, do nothing.",
        parameters: Schema(type: .object)
    )

    static let stopPointing = FunctionDeclaration(
        name: "stop_pointing",
        description: "Hide the halo and stop pointing at the current element. Use when the user says \"stop showing me that\", \"ok I see it\", \"you can stop pointing now\". Does NOT end the session or any lesson — you can call point_to_element again later.",
        parameters: Schema(type: .object)
    )

    static let listLessons = FunctionDeclaration(
        name: "list_lessons",
        description: "Return the catalog of available lessons. Each entry has an id, title, app, and estimated_minutes. Call this to discover which lessons you can offer the user, or when they ask \"what can you teach me?\"",
        parameters: Schema(type: .object)
    )

    static let startLesson = FunctionDeclaration(
        name: "start_lesson",
        description: "Begin a lesson. Provide either `lesson_id` (from the catalog) or `topic` (ad-hoc — you improvise the lesson). Returns lesson_already_active if a lesson is running — call exit_lesson first.",
        parameters: Schema(
            type: .object,
            properties: [
                "lesson_id": Schema(
                    type: .string,
                    description: "The id of a cataloged lesson (from list_lessons). Mutually exclusive with topic."
                ),
                "topic": Schema(
                    type: .string,
                    description: "A free-form topic for an ad-hoc lesson (no YAML needed). Mutually exclusive with lesson_id."
                )
            ]
        )
    )

    static let advanceLessonStep = FunctionDeclaration(
        name: "advance_lesson_step",
        description: "Move to a specific step in the active lesson, or finish it. In a curated lesson, `to_step` is a 0-based index. In an ad-hoc lesson (one you improvised), call with no args to bump the step counter, or with `finish: true` to end. Returns no_active_lesson if no lesson is running.",
        parameters: Schema(
            type: .object,
            properties: [
                "to_step": Schema(
                    type: .integer,
                    description: "Absolute 0-based step index. Defaults to current+1 if omitted. Can go backward (replay)."
                ),
                "finish": Schema(
                    type: .boolean,
                    description: "If true, finish the lesson regardless of to_step."
                )
            ]
        )
    )

    static let all: [Tool] = [
        Tool(functionDeclarations: [
            getUITree, pointToElement,
            startTour, stopTour, resumeTour,
            exitLesson, stopPointing,
            listLessons, startLesson, advanceLessonStep
        ])
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

struct StartLessonArgs: Decodable {
    let lesson_id: String?
    let topic: String?
}

struct AdvanceLessonStepArgs: Decodable {
    let to_step: Int?
    let finish: Bool?
}
