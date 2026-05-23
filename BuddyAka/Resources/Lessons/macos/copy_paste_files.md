---
id: macos.copy_paste_files
title: Copy and paste files in Finder
language_hints:
  uz: Finder'da fayllarni nusxalash va joylashtirish
  ru: Копирование и вставка файлов в Finder
app:
  bundle_id: com.apple.finder
prerequisites:
  - You have at least one file on your Mac
estimated_minutes: 2
sort_order: 22
suggested_next:
  - macos.connect_to_wifi
---

# Copy and paste files in Finder

By the end of this lesson the learner has opened Finder, navigated to a folder, selected a file, copied it, navigated to another folder, and pasted it. This is the most fundamental file operation on a Mac — and the keyboard shortcut is the same one that works almost everywhere.

**Teaching stance:** This is the simplest lesson. Many learners may have never used keyboard shortcuts before. Be patient and explicit about which keys to press. Don't assume they know where Cmd is on the keyboard — point it out.

## Step 1 — Open Finder

> Click the Finder icon in your Dock — it's the blue-and-white smiley face, usually the first icon on the left. A Finder window opens showing your files.

**Teach:** Finder is like a filing cabinet for your Mac. Every file and folder on your computer can be found through Finder.

```yaml
expect:
  match:
    scope: dock
    any_of:
      - { label_contains: "Finder" }
      - { label: "Finder" }
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Step 2 — Go to your Documents folder

> In the left sidebar of the Finder window, click "Documents". If you don't see a sidebar, press Cmd+Option+S to show it.

**Teach:** The sidebar is your quick-access panel. It shows your most-used folders — Documents, Downloads, Desktop — so you don't have to dig through nested folders to get to them.

```yaml
expect:
  match:
    any_of:
      - { label_contains: "Documents" }
      - { label_contains: "Документы" }
      - { label_contains: "Hujjatlar" }
  advance_when: focused_element_changes
```

## Step 3 — Select a file

> Click once on any file in the Documents folder. The file highlights in blue — that means it's selected.

**Teach:** One click selects a file. Double-click opens it. This is a common confusion for beginners, so remember: one click to pick, two clicks to open.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 4 — Copy the file

> Press Cmd+C on your keyboard. Nothing visible happens — that's normal. Your Mac has remembered that file and is ready to paste a copy of it.

**Teach:** The Cmd key is right next to the spacebar, with a ⌘ symbol on it. Cmd+C means "copy" and it works everywhere on a Mac — files, text, images.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 5 — Navigate to the Desktop folder

> In the left sidebar, click "Desktop". You're now looking at a different folder.

```yaml
expect:
  match:
    any_of:
      - { label_contains: "Desktop" }
      - { label_contains: "Рабочий стол" }
      - { label_contains: "Ish stoli" }
  advance_when: focused_element_changes
```

## Wrap-up

> Now press Cmd+V to paste. A copy of your file appears on the Desktop. That's it — Cmd+C to copy, Cmd+V to paste. The original file stays where it was. These two shortcuts work with files, text, images — anything on your Mac. If you ever want to MOVE a file instead of copying it, just drag it from one folder to another.
