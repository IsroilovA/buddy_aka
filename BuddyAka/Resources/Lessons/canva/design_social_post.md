---
id: canva.design_social_post
title: Design a social media post
language_hints:
  uz: Ijtimoiy tarmoq posti yarating
  ru: Создайте пост для соцсетей
app:
  url_match: canva.com
prerequisites:
  - You have an internet connection and a Canva account
estimated_minutes: 5
sort_order: 13
suggested_next:
  - canva.presentation
  - figma.design_a_shape
---

# Design a social media post

By the end of this lesson the learner has picked a template, edited the headline text, changed a color, and downloaded the finished image. Canva makes professional-looking graphics accessible to anyone — this lesson proves that in under five minutes.

**Teaching stance:** Canva is designed to be friendly, so lean into that energy. Celebrate how fast good-looking results come together. Don't worry about design theory — focus on the mechanics of finding, editing, and exporting.

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

## Step 2 — Go to Canva

> Click the address bar and type "canva.com" then press Return.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Address" }
  advance_when: url_contains
  advance_value: canva.com
```

## Step 3 — Start a new design

> On the Canva homepage, look for the purple "Create a design" button in the top-right area. Click it, then choose "Instagram Post" or "Custom size" from the dropdown.

**Teach:** Canva offers preset sizes for every platform — Instagram, Facebook, YouTube thumbnails, posters. Picking the right size means your image won't get cropped when you upload it.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label_contains: "Create a design" }
      - { label_contains: "Создать дизайн" }
      - { label_contains: "Dizayn yaratish" }
  advance_when: window_changes
  also_advance_when: url_contains
  also_advance_value: canva.com/design
```

## Step 4 — Pick a template

> On the left panel, you'll see a grid of templates. Scroll through and click one that catches your eye. It loads onto the canvas instantly.

**Teach:** Templates are pre-made designs by professional designers. You're not copying — you're customizing. Every font, color, and image in the template can be changed.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 5 — Edit the headline text

> Double-click the big text on the canvas — it becomes editable. Select all the text and type your own headline. Something like "Weekend Sale" or "New Podcast Episode".

**Teach:** Double-clicking any text in Canva lets you edit it. You can also change the font, size, and color in the toolbar that appears above.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 6 — Change a color

> Click on a colored shape or background area in the template. In the toolbar that appears at the top, find the color swatch (a small colored square). Click it and pick a new color.

**Teach:** Consistent colors make designs look polished. Canva suggests color palettes that work well together — you don't need to guess.

```yaml
expect:
  advance_when: focused_element_changes
  also_advance_when: window_changes
```

## Step 7 — Download your design

> Click the "Share" button in the top-right corner, then click "Download". Make sure the format says PNG, then click the purple "Download" button.

**Teach:** PNG gives you a crisp image perfect for social media. If you ever need a smaller file, try JPG instead.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label_contains: "Download" }
      - { label_contains: "Скачать" }
      - { label_contains: "Yuklab olish" }
      - { label_contains: "Share" }
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Wrap-up

> That's a finished social media graphic, designed and downloaded in a few minutes. You picked a template, made it yours with custom text and colors, and exported it. That's the entire Canva workflow — now you can make posts, stories, flyers, anything.
