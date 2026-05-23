---
id: photopea.remove_background
title: Remove a photo background in one click
language_hints:
  uz: Bir bosishda fon olib tashlash
  ru: Удалить фон одним кликом
app:
  url_match: photopea.com
prerequisites:
  - You have an internet connection
  - You have a photo file on your Mac to open
estimated_minutes: 4
sort_order: 11
suggested_next:
  - photopea.export_transparent_png
---

# Remove a photo background in one click

By the end the learner has erased the background from a photo and seen the checkerboard pattern that signals transparency. Photopea has a one-click "Remove BG" command — same job as the paid Photoshop version, free in your browser.

**Teaching stance:** This is a wow-factor lesson — keep it short and let the AI selection do the talking. Celebrate the moment the background disappears. Don't get philosophical about layers and masks unless asked.

## Step 1 — Open Safari

> Click the Safari icon in your Dock — the blue compass. If you don't see it there, press Cmd+Space, type "Safari", and press Return.

```yaml
expect:
  match:
    scope: dock
    label_contains: Safari
  advance_when: focused_element_changes
  also_advance_when: window_changes
```

## Step 2 — Click the address bar

> Click the wide text box at the top of Safari — the URL bar.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Search or enter" }
      - { label_contains: "Smart Search" }
      - { label_contains: "Address" }
  advance_when: focused_element_changes
```

## Step 3 — Type photopea.com and press Return

> Type "photopea.com" and press Return. The site loads with no signup or payment.

```yaml
expect:
  advance_when: url_contains
  advance_value: photopea.com
```

## Step 4 — Open a photo

> When Photopea opens, you'll see a splash screen. Click "Open From Computer" and pick any photo with a clear subject — a person, a pet, a coffee cup.

**Teach:** Photopea works on your file locally — nothing gets uploaded. The image stays on your Mac.

```yaml
expect:
  match:
    scope: app_window
    role: button
    label_contains: Open From Computer
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Step 5 — Open the Select menu

> Click on the word "Select" in the menu bar at the top of Photopea. It's between "Image" and "Filter".

**Teach:** The Select menu holds every command that's about choosing which part of the image you want to work on. "Remove BG" lives here because it's really a selection that immediately deletes itself.

```yaml
expect:
  match:
    scope: app_window
    role: button
    label: Select
  advance_when: focused_element_changes
```

## Step 6 — Click Remove BG

> Near the bottom of the menu that just opened, find "Remove BG" and click it.

**Teach:** Photopea sends your image to an AI model that figures out which pixels are subject and which are background, then deletes the background automatically. Takes a few seconds.

```yaml
expect:
  match:
    role: menu_item
    label_contains: Remove BG
  advance_when: focused_element_changes
```

## Step 7 — Wait for the AI to finish

> Watch the image — in a few seconds the background will turn into a grey-and-white checkerboard. That checkerboard means "nothing's there" — the background is gone.

**Teach:** This is the wait. Don't keep clicking — Photopea is doing real work and a second click can confuse it.

```yaml
expect:
  advance_when: window_changes
```

## Step 8 — File → Export As → PNG → Save

> Click "File" in the menu bar, hover "Export As", click "PNG", and in the dialog that opens click the green "Save" button.

**Teach:** PNG is the format that preserves transparency. JPG would fill the transparent areas back with white.

```yaml
expect:
  match:
    role: button
    label: Save
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Wrap-up

> Your transparent PNG just downloaded — check your Downloads folder. You can drop it onto any background, any document, any presentation, and the subject sits cleanly on top with no white box around it. That's the bread-and-butter trick of every product photo on the web.
