---
id: macos.connect_to_wifi
title: Join a Wi-Fi network
language_hints:
  uz: "Wi-Fi tarmog'iga ulanish"
  ru: Подключиться к Wi-Fi
app:
  bundle_id: com.apple.systempreferences
prerequisites:
  - You can hear audio from BuddyAka
estimated_minutes: 3
sort_order: 23
suggested_next:
  - macos.bluetooth_pairing
---

# Join a Wi-Fi network

By the end the learner has clicked into the Wi-Fi panel, found the network list, and knows where to click to join one. This is a "where do I find things" lesson aimed at people who are new to macOS or who haven't opened System Settings since the redesign.

**Teaching stance:** Patient, grounded, no jargon. Many learners are older adults or recent macOS switchers — never assume they know what a sidebar is or where the Apple menu lives. Tell them what to LOOK for, not what to click on, since the halo may sometimes miss in this app.

## Step 0 — Open System Settings (setup helper)

> Let's open System Settings. The fastest path is clicking the Apple menu in the very top-left of your screen — that's the small Apple icon. Then choose "System Settings…" near the top of the dropdown. If you see a Settings cog in your Dock, you can click that instead.

**Teach:** macOS always shows the Apple menu at the very top-left of the screen, no matter which app is in front. It's the universal "system stuff" entry point.

```yaml
expect:
  match:
    any_of:
      - { scope: menu_bar, role: menu_item, label: "" }
      - { scope: menu_bar, role: menu_item, label_contains: "Apple" }
      - { scope: dock, label_contains: "System Settings" }
      - { scope: dock, label_contains: "System Preferences" }
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Step 1 — Click Wi-Fi in the sidebar

> Look at the list on the left side of the window. Find "Wi-Fi" — it's usually near the top, marked with a small fan-shape icon. Click it.

**Teach:** The sidebar groups every macOS setting by topic. Wi-Fi has its own panel because it's one of the things you'll likely touch most often.

```yaml
expect:
  match:
    any_of:
      - { label: "Wi-Fi" }
      - { label_contains: "Wi" }
  advance_when: focused_element_changes
```

## Step 2 — Find the Wi-Fi toggle

> At the very top of the right side, there's a switch labeled "Wi-Fi" with a blue or grey background. If it's grey, click it once to turn Wi-Fi on — if it's blue, you're good.

**Teach:** This is the master switch for your Mac's Wi-Fi radio. When it's off, no network in the world will show up below. Don't worry about toggling it back and forth — Macs handle that fine.

```yaml
expect:
  match:
    role: switch
    label_contains: "Wi"
  advance_when: focused_element_changes
```

## Step 3 — Look at the list of nearby networks

> Below the toggle, you'll see a list of network names — these are every Wi-Fi network your Mac can see right now. Your home network is somewhere in this list.

**Teach:** Each row is one nearby network. The icon on the right shows how strong the signal is — full bars means a strong connection, fewer bars means farther away. A lock icon means the network needs a password.

```yaml
expect:
  match:
    any_of:
      - { label_contains: "Other Networks" }
      - { label_contains: "Networks" }
  advance_when: focused_element_changes
```

## Step 4 — Click the network you want to join

> Find your home network's name in that list and click it. If it has a lock icon, a small password box will pop up.

**Teach:** macOS remembers any network you join. Next time you're in range it'll connect on its own without asking again.

```yaml
expect:
  advance_when: window_changes
```

## Step 5 — Type the password and click Join

> In the password box, type the Wi-Fi password — the characters will show as dots. Then click the blue "Join" button.

**Teach:** The dots are just to keep someone from reading your password over your shoulder. If you mistype, the box will say so — just try again.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label: Join }
      - { label: Подключиться }
      - { label: Ulanish }
  advance_when: focused_element_changes
```

## Wrap-up

> You're on. The icon in the top-right of your screen — the little fan shape — now shows that network. The next time you open your Mac in this spot, it'll connect on its own.
