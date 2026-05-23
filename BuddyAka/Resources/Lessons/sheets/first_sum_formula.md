---
id: sheets.first_sum_formula
title: Your first SUM formula
language_hints:
  uz: Birinchi SUM formulangiz
  ru: Ваша первая формула SUM
app:
  url_match: docs.google.com/spreadsheets
prerequisites:
  - You have an internet connection and a Google account
estimated_minutes: 6
sort_order: 14
suggested_next:
  - sheets.cell_references
  - sheets.average_and_count
---

# Your first SUM formula

By the end of this lesson the learner has typed a working =SUM formula and seen the result appear in the cell. SUM is the foundation of every spreadsheet skill — budgets, grade books, inventories all build on it.

**Teaching stance:** Be encouraging and concrete. Formulas look like code, which intimidates first-timers — frame them as calculators that live inside a cell. Celebrate small wins. Never lecture; react.

## Step 1 — Open Safari

> Click the Safari icon in your Dock — the blue compass. If you don't see it there, press Cmd+Space, type "Safari", and press Return.

**Teach:** Safari is the web browser built into every Mac. You'll find its icon in the Dock at the bottom of the screen.

```yaml
expect:
  match:
    scope: dock
    label_contains: Safari
  advance_when: focused_element_changes
  also_advance_when: window_changes
```

## Step 2 — Click the address bar

> Click the wide text box at the top of Safari — it says "Search or enter website name". That's the URL bar.

**Teach:** The URL bar is where you type web addresses. It doubles as a search box if you just type words.

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

## Step 3 — Type sheets.new and press Return

> Type the word "sheets.new" — no spaces, just like a normal web address — then press Return.

**Teach:** "sheets.new" is a Google shortcut that opens a brand new blank spreadsheet. No need to click around in menus.

```yaml
expect:
  advance_when: url_contains
  advance_value: docs.google.com/spreadsheets
```

## Step 4 — Open the Insert menu

> Click on the word "Insert" in the menu bar at the top — it sits between "View" and "Format".

**Teach:** The menu bar is where Sheets keeps every command grouped by topic — Insert is for adding rows, columns, charts, and functions.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label: Insert }
      - { label: Вставка }
      - { label: "Qo'shish" }
  advance_when: focused_element_changes
```

## Step 5 — Hover Function, then click SUM

> In the menu that opened, hover on "Function". A second menu pops out — at the very top is "SUM". Click it.

**Teach:** Sheets has hundreds of functions; SUM is the most-used. Picking it from the menu types the formula skeleton =SUM() into your active cell for you — you don't have to remember the spelling.

```yaml
expect:
  match:
    role: menu_item
    any_of:
      - { label: SUM }
      - { label: СУММ }
  advance_when: focused_element_changes
```

## Step 6 — Type numbers separated by commas

> Sheets just typed =SUM( for you in a cell. Type a few numbers separated by commas — try 10, 20, 30, 40, 50 — then type a closing parenthesis.

**Teach:** The commas tell SUM where one number ends and the next begins. Every Sheets function uses commas the same way. The closing paren tells Sheets you're done listing.

```yaml
expect:
  match:
    role: text_field
    label_contains: Formula
  advance_when: value_contains
  advance_value: ")"
```

## Step 7 — Press Enter to compute the result

> Press the Enter key. The formula disappears and the cell shows the total — if you used my example, you should see 150.

**Teach:** This is the magic moment. The cell remembers the formula (you can see it in the formula bar above whenever you click back), but it shows you the answer. Change any of the numbers later and the answer updates on its own.

```yaml
expect:
  match:
    role: text_field
    label_contains: Formula
  advance_when: value_equals
  advance_value: ""
  also_advance_when: focused_element_changes
```

## Wrap-up

> That's your first formula. Try clicking back on that cell — you'll see =SUM(...) reappear in the formula bar at the top. The cell remembers the recipe, not the answer. That's the trick that makes spreadsheets powerful.
