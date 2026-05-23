---
id: google_slides.first_presentation
title: Create your first presentation
language_hints:
  uz: Birinchi taqdimotingizni yarating
  ru: Создайте первую презентацию
app:
  url_match: docs.google.com/presentation
prerequisites:
  - You have an internet connection and a Google account
estimated_minutes: 5
sort_order: 15
suggested_next:
  - google_slides.add_images
  - google_docs.write_and_format
---

# Create your first presentation

By the end of this lesson the learner has created a Google Slides presentation, typed a title, added a new slide, inserted a text box, and applied a theme. These are the building blocks of every slideshow — from school projects to boardroom pitches.

**Teaching stance:** Slides is visual and forgiving — anything you type can be moved, resized, or deleted. Encourage experimentation. If the learner asks about animations or transitions, say "great idea, let's finish the basics first."

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

## Step 2 — Go to Google Slides

> Click the address bar at the top and type "slides.new" then press Return. This creates a brand new blank presentation.

**Teach:** Just like "sheets.new" for spreadsheets, "slides.new" is a Google shortcut that creates a fresh presentation in one step. No clicking through menus.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Address" }
  advance_when: url_contains
  advance_value: docs.google.com/presentation
```

## Step 3 — Type a title

> You'll see a big placeholder that says "Click to add title". Click on it and type something — maybe "My First Presentation" or "Weekend Plans".

**Teach:** The title slide is the first thing your audience sees. Keep it short and clear. You can always change it later.

```yaml
expect:
  match:
    any_of:
      - { label_contains: "title" }
      - { label_contains: "Title" }
      - { label_contains: "заголовок" }
  advance_when: focused_element_changes
```

## Step 4 — Add a subtitle

> Below the title, there's a smaller placeholder that says "Click to add subtitle". Click it and type a short subtitle — your name, a date, or a tagline.

```yaml
expect:
  match:
    any_of:
      - { label_contains: "subtitle" }
      - { label_contains: "Subtitle" }
      - { label_contains: "подзаголовок" }
  advance_when: focused_element_changes
```

## Step 5 — Add a new slide

> Look at the toolbar near the top. Find the "New slide" button — it has a plus icon. Click it to add a second slide.

**Teach:** Each slide is one screen of your presentation. A typical slideshow has 10–20 slides, but even two is a complete presentation if the content is good.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label_contains: "New slide" }
      - { label_contains: "Новый слайд" }
      - { label_contains: "Yangi slayd" }
  advance_when: focused_element_changes
```

## Step 6 — Type in the new slide

> The new slide has its own text placeholders. Click on the title area and type a heading for this slide — something like "Key Points" or "What I Learned".

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 7 — Apply a theme

> Click on "Slide" in the menu bar at the top, then click "Change theme". A panel opens on the right with pre-designed themes — click one you like.

**Teach:** Themes set the fonts, colors, and background for every slide at once. You can always switch themes later without losing your text.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label: Slide }
      - { label: "Слайд" }
      - { label: "Slayd" }
  advance_when: focused_element_changes
  also_advance_when: window_changes
```

## Wrap-up

> You just built a real presentation — title slide, content slide, and a professional theme. Every great slideshow is just more of the same: add slides, type content, pick visuals. You now know the loop.
