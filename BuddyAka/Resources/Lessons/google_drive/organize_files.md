---
id: google_drive.organize_files
title: Organize files in Google Drive
language_hints:
  uz: Google Drive'da fayllarni tartibga soling
  ru: Организуйте файлы в Google Диске
app:
  url_match: drive.google.com
prerequisites:
  - You have an internet connection and a Google account
estimated_minutes: 4
sort_order: 18
suggested_next:
  - google_docs.write_and_format
  - sheets.first_sum_formula
---

# Organize files in Google Drive

By the end of this lesson the learner has opened Google Drive, created a folder, renamed it, uploaded a file, and moved that file into the folder. These are the basic file-management skills that keep your cloud storage usable as it grows.

**Teaching stance:** Drive is just a file system in the cloud — if the learner has ever used Finder, the concepts are the same. Folders hold files, drag-and-drop works. Keep things simple and practical.

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

## Step 2 — Go to Google Drive

> Click the address bar and type "drive.google.com" then press Return.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Address" }
  advance_when: url_contains
  advance_value: drive.google.com
```

## Step 3 — Create a new folder

> Look for the "+ New" button in the top-left area of Drive. Click it, then choose "New folder" from the dropdown menu.

**Teach:** Folders in Drive work just like folders on your computer. They group related files together so you can find them later. Think of them as labeled boxes.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label_contains: "New" }
      - { label_contains: "Создать" }
      - { label_contains: "Yangi" }
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Step 4 — Name the folder

> A dialog pops up asking for a folder name. Type something like "My Projects" or "Test Folder" then click the "Create" button.

```yaml
expect:
  match:
    role: text_field
    any_of:
      - { label_contains: "folder" }
      - { label_contains: "Untitled" }
      - { label_contains: "name" }
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Step 5 — Upload a file

> Click "+ New" again, then choose "File upload". A file picker opens — select any file from your Mac and click "Open".

**Teach:** Uploaded files live in Google's cloud, so you can access them from any device with a browser. The original file stays on your Mac too — Drive makes a copy.

```yaml
expect:
  match:
    any_of:
      - { role: button, label_contains: "File upload" }
      - { role: button, label_contains: "Загрузить" }
      - { role: button, label_contains: "Fayl yuklash" }
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Step 6 — Move the file into the folder

> Find your uploaded file in the list. Right-click on it (or Control-click), then choose "Move to" or "Organize". Select the folder you just created and click "Move".

**Teach:** Moving files in Drive is non-destructive — the file doesn't change, it just gets a new home. You can always move it again or put it in multiple folders using shortcuts.

```yaml
expect:
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Wrap-up

> Your Drive now has a folder with a file in it. That's the whole organizing pattern — create folders, upload files, move them where they belong. The more consistent you are about this, the easier it gets to find things months later.
