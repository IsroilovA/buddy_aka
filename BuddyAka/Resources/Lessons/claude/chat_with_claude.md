---
id: claude.chat_with_claude
title: Chat with Claude AI
language_hints:
  uz: Claude AI bilan suhbatlashing
  ru: Поговорите с Claude AI
app:
  url_match: claude.ai
prerequisites:
  - You have an internet connection and an Anthropic account
estimated_minutes: 3
sort_order: 21
suggested_next:
  - chatgpt.first_question
---

# Chat with Claude AI

By the end of this lesson the learner has opened Claude, typed a message, read the response, and started a new conversation. Claude is an AI assistant made by Anthropic — this lesson builds confidence in talking to it naturally.

**Teaching stance:** Claude responds well to natural language, so encourage the learner to write like they're talking to a person, not a search engine. Celebrate the first response — it's a "wow" moment for newcomers.

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

## Step 2 — Go to Claude

> Click the address bar and type "claude.ai" then press Return. Log in if prompted.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Address" }
  advance_when: url_contains
  advance_value: claude.ai
```

## Step 3 — Type a message

> You'll see a text area at the bottom of the page. Click it and type something — try "What are three interesting facts about the moon?" or "Help me write a birthday message for a friend."

**Teach:** Claude works best when you're specific. Instead of "Tell me about history," try "Explain why the Silk Road was important in three sentences." The clearer your prompt, the better the answer.

```yaml
expect:
  match:
    any_of:
      - { role: text_field, label_contains: "Reply" }
      - { role: text_field, label_contains: "Message" }
      - { role: text_field, label_contains: "Claude" }
  advance_when: focused_element_changes
```

## Step 4 — Send your message

> Press Return or click the send button to submit. Claude's response appears below your message, streaming in as it writes.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 5 — Start a new conversation

> In the left sidebar, look for a "New chat" button or a compose icon. Click it to open a fresh conversation.

**Teach:** Each conversation is independent — Claude won't carry over context from your last chat. This is useful when you switch topics. Your old conversations stay in the sidebar history.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label_contains: "New chat" }
      - { label_contains: "Start" }
      - { label_contains: "New" }
  advance_when: focused_element_changes
```

## Wrap-up

> You just had your first conversation with Claude. Try asking it to explain something you're studying, help draft an email, or compare two options you're deciding between. The more you use it, the better you'll get at asking questions that get useful answers.
