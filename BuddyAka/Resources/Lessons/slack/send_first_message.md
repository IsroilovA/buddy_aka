---
id: slack.send_first_message
title: Send your first Slack message
language_hints:
  uz: Slack'da birinchi xabaringizni yuboring
  ru: Отправьте первое сообщение в Slack
app:
  url_match: app.slack.com
prerequisites:
  - You have an internet connection and access to a Slack workspace
estimated_minutes: 4
sort_order: 17
suggested_next:
  - slack.threads_and_reactions
---

# Send your first Slack message

By the end of this lesson the learner has opened Slack in the browser, clicked into a channel, typed and sent a message, and added an emoji reaction. These four actions are the daily rhythm of Slack — everything else (threads, files, calls) builds on them.

**Teaching stance:** Slack can feel overwhelming at first — there are channels, DMs, threads, and notifications everywhere. Keep the focus narrow: one channel, one message, one reaction. Don't explain threads or settings unless the learner asks.

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

## Step 2 — Go to Slack

> Click the address bar and type "app.slack.com" then press Return. If you're logged in, your workspace will load.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Address" }
  advance_when: url_contains
  advance_value: app.slack.com
```

## Step 3 — Click a channel

> On the left sidebar you'll see a list of channels — they start with a # symbol. Click on any channel — if you see #general or #random, those are good places to start.

**Teach:** Channels are group conversations organized by topic. #general is where team-wide announcements go. You can browse and join channels freely — you're not intruding.

```yaml
expect:
  match:
    any_of:
      - { role: link, label_contains: "general" }
      - { role: link, label_contains: "random" }
      - { role: button, label_contains: "general" }
  advance_when: focused_element_changes
```

## Step 4 — Type a message

> At the bottom of the screen you'll see a text box that says "Message #channel-name". Click it and type a message — try "Hello from BuddyAka!" or just "Hi everyone."

**Teach:** The message box is always at the bottom of a channel. You can type multiple lines by pressing Shift+Return. Regular Return sends the message.

```yaml
expect:
  match:
    any_of:
      - { role: text_field, label_contains: "Message" }
      - { role: text_field, label_contains: "Сообщение" }
      - { role: text_field, label_contains: "Xabar" }
  advance_when: focused_element_changes
```

## Step 5 — Send it

> Press Return to send your message. It appears in the channel immediately — everyone in the channel can see it.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 6 — Add an emoji reaction

> Hover your mouse over the message you just sent. A small toolbar appears — look for the smiley face icon and click it. Pick any emoji from the picker that opens.

**Teach:** Emoji reactions are how people in Slack say "got it", "thanks", or "funny" without writing a full reply. They keep channels tidy by reducing one-word messages.

```yaml
expect:
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Wrap-up

> You just sent a message and reacted to it in Slack. That's the core loop — open a channel, type, send, react. Everything else in Slack is a variation on this: threads are replies to a specific message, DMs are private channels with one person, and files are just messages with attachments.
