---
id: jira.create_first_task
title: Create your first Jira task
language_hints:
  uz: Jira'da birinchi vazifangizni yarating
  ru: Создайте первую задачу в Jira
app:
  url_match: atlassian.net
prerequisites:
  - You have an internet connection and a Jira account
estimated_minutes: 4
sort_order: 12
suggested_next:
  - jira.manage_board
---

# Create your first Jira task

By the end of this lesson the learner has opened Jira, created an issue with a title and description, set its priority, and assigned it. This is the core loop of project management — everything else builds on knowing how to create and describe a task.

**Teaching stance:** Jira has a lot of fields and options. Most of them are optional. Keep the learner focused on the three things that matter: what needs to be done (summary), why (description), and how urgent (priority). Don't get into sprints, epics, or story points unless asked.

## Step 1 — Open Safari

> Click the Safari icon in your Dock — the blue compass.

```yaml
expect:
  match:
    scope: dock
    label_contains: Safari
  advance_when: focused_element_changes
  also_advance_when: window_changes
```

## Step 2 — Go to your Jira board

> Click the address bar and type your Jira URL — it looks like "yourteam.atlassian.net" — then press Return. If you're already logged in, you'll see your project board.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Address" }
  advance_when: url_contains
  advance_value: atlassian.net
```

## Step 3 — Click the Create button

> Look for the blue "Create" button near the top of the page. It might also appear as a plus icon in the top navigation bar. Click it.

**Teach:** The Create button opens a form where you describe what needs to be done. In Jira, every piece of work is called an "issue" — it could be a bug, a task, or a feature request.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label: Create }
      - { label_contains: "Create" }
      - { label: "Создать" }
      - { label: "Yaratish" }
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Step 4 — Type a summary

> In the "Summary" field at the top of the form, type a short title for your task — for example, "Update the homepage banner". Keep it short and clear.

**Teach:** The summary is the title everyone sees on the board. A good summary answers "what needs to happen" in one line. You can always add details in the description.

```yaml
expect:
  match:
    role: text_field
    any_of:
      - { label_contains: "Summary" }
      - { label_contains: "Сводка" }
      - { label_contains: "Xulosa" }
  advance_when: focused_element_changes
```

## Step 5 — Add a description

> Click the "Description" area below the summary. Type a sentence or two about what this task involves — for example, "Replace the current banner image with the new branding."

**Teach:** The description is where you give context. Whoever picks up this task later will read this to understand what to do. Even a single sentence is better than nothing.

```yaml
expect:
  match:
    any_of:
      - { role: text_field, label_contains: "Description" }
      - { role: generic, label_contains: "Description" }
  advance_when: focused_element_changes
```

## Step 6 — Set the priority

> Find the "Priority" dropdown — it usually shows "Medium" by default. Click it and choose a priority level. "Medium" is fine for practice.

**Teach:** Priority tells your team how urgent this task is. Most teams use High for blockers, Medium for normal work, and Low for nice-to-haves. When in doubt, Medium is safe.

```yaml
expect:
  match:
    any_of:
      - { label_contains: "Priority" }
      - { label_contains: "Приоритет" }
      - { label_contains: "Ustuvorlik" }
  advance_when: focused_element_changes
```

## Step 7 — Click Create to save

> Scroll to the bottom of the form and click the blue "Create" button. Your task now appears on the board.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label: Create }
      - { label: Submit }
      - { label: "Создать" }
      - { label: "Yaratish" }
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Wrap-up

> You just created your first Jira task. It's now sitting on the board where your team can see it, pick it up, and track progress. Every project — from building an app to planning a party — starts with one task like this.
