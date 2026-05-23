---
id: figma.design_a_shape
title: Design a shape in Figma
language_hints:
  uz: Figmada shakl yaratish
  ru: Создайте фигуру в Figma
app:
  url_match: figma.com
prerequisites:
  - You have an internet connection and a Figma account
estimated_minutes: 5
sort_order: 10
suggested_next:
  - figma.auto_layout
  - canva.design_social_post
---

# Design a shape in Figma

By the end of this lesson the learner has created a new Figma file, placed a frame, drawn a rectangle, changed its fill color, added a text label, and exported the result as PNG. These are the absolute basics every Figma workflow builds on.

**Teaching stance:** Figma's interface is dense — toolbars, panels, layers. Keep the learner focused on one thing at a time. Name what to look for on screen before asking them to click. Celebrate the first shape appearing on the canvas.

## Step 1 — Open Safari

> Click the Safari icon in your Dock — the blue compass. If you don't see it, press Cmd+Space, type "Safari", and press Return.

```yaml
expect:
  match:
    scope: dock
    label_contains: Safari
  advance_when: focused_element_changes
  also_advance_when: window_changes
```

## Step 2 — Go to Figma

> Click the address bar at the top of Safari and type "figma.com" then press Return.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Address" }
  advance_when: url_contains
  advance_value: figma.com
```

## Step 3 — Create a new design file

> Once Figma loads, look for a button that says "New design file" or a big plus icon. Click it to create a blank canvas.

**Teach:** Figma files live in the cloud — you don't need to save manually. Everything you draw is saved automatically.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label_contains: "New design file" }
      - { label_contains: "design file" }
      - { label_contains: "New" }
  advance_when: url_contains
  advance_value: figma.com/design
```

## Step 4 — Add a frame

> Press the letter F on your keyboard, or click the frame tool in the top toolbar — it looks like a hash symbol. Then click and drag on the canvas to draw a frame.

**Teach:** A frame in Figma is like a page or an artboard. Everything you design goes inside a frame. Think of it as the boundaries of your design.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 5 — Draw a rectangle

> Press R on your keyboard to switch to the rectangle tool. Click and drag inside the frame to draw a rectangle.

**Teach:** Keyboard shortcuts make Figma fast — R for rectangle, T for text, F for frame. You'll memorize them naturally as you use the tool.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 6 — Change the fill color

> With the rectangle selected, look at the right panel. Find the "Fill" section — it shows a small colored square. Click that square to open the color picker, then pick any color you like.

**Teach:** The right panel is the properties inspector — it shows details about whatever you have selected. Fill is the shape's background color.

```yaml
expect:
  advance_when: focused_element_changes
  also_advance_when: window_changes
```

## Step 7 — Add a text label

> Press T on your keyboard to switch to the text tool. Click somewhere on your frame and type a word — your name, "Hello", anything you like.

**Teach:** Text in Figma is just another object on the canvas. You can move, resize, and style it the same way you would a shape.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 8 — Export as PNG

> Click on the frame to select it (not the rectangle or text — the whole frame). In the right panel, scroll down to "Export". Click the plus button next to it, make sure it says PNG, then click "Export frame".

**Teach:** Export turns your Figma design into an image file. PNG is the most common format for web graphics because it supports transparency.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label_contains: "Export" }
      - { label_contains: "export" }
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Wrap-up

> You just designed your first thing in Figma — a colored shape with a label, exported as a real image file. Every app icon, website mockup, and presentation graphic starts exactly like this: a frame, some shapes, some text. Now you know where everything lives.
