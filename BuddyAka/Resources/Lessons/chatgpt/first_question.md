---
id: chatgpt.first_question
title: Ask ChatGPT your first question
language_hints:
  uz: ChatGPT'ga birinchi savolingizni bering
  ru: Задайте ChatGPT первый вопрос
app:
  url_match: chatgpt.com
prerequisites:
  - You have an internet connection and an OpenAI account
estimated_minutes: 3
sort_order: 20
suggested_next:
  - claude.chat_with_claude
---

# Ask ChatGPT your first question

By the end of this lesson the learner has opened ChatGPT, typed a question, read the response, and started a new conversation. These are the basics of interacting with an AI assistant — framing a question, reading the output, and knowing how to reset for a fresh topic.

**Teaching stance:** AI chat is new to many people and can feel strange. Normalize it — it's like a search engine that talks back in full sentences. Encourage the learner to ask anything, even "What can you do?" The point is building comfort, not getting a perfect answer.

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

## Step 2 — Go to ChatGPT

> Click the address bar and type "chatgpt.com" then press Return. Log in if asked.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Address" }
  advance_when: url_contains
  advance_value: chatgpt.com
```

## Step 3 — Type a question

> You'll see a text box at the bottom of the page. Click it and type a question — try something simple like "What is the capital of Uzbekistan?" or "Explain photosynthesis in one sentence."

**Teach:** The text box is where you "prompt" the AI. A prompt is just a question or instruction written in plain language. The more specific your prompt, the more useful the answer.

```yaml
expect:
  match:
    any_of:
      - { role: text_field, label_contains: "Message" }
      - { role: text_field, label_contains: "Ask" }
      - { role: text_field, label_contains: "Send" }
  advance_when: focused_element_changes
```

## Step 4 — Send your question

> Press Return or click the send button (the small arrow icon) to submit your question. ChatGPT starts typing its answer immediately — watch it appear word by word.

**Teach:** ChatGPT generates its response one piece at a time. If the answer is long, you can scroll down as it writes. If it stops mid-sentence, just wait — it's still thinking.

```yaml
expect:
  advance_when: focused_element_changes
```

## Step 5 — Start a new conversation

> In the left sidebar, look for a button that says "New chat" or has a pencil/compose icon. Click it to start a fresh conversation on a different topic.

**Teach:** Each conversation in ChatGPT is separate. Starting a new chat gives you a clean slate — the AI won't remember your previous questions. Your old conversations are saved in the sidebar if you need them.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label_contains: "New chat" }
      - { label_contains: "new chat" }
      - { label_contains: "New" }
  advance_when: focused_element_changes
```

## Wrap-up

> You just had your first AI conversation. You asked a question, got an answer, and started fresh. That's the entire workflow. Try asking for help with homework, writing an email, brainstorming ideas, or explaining something confusing — AI assistants are most useful when you treat them like a patient, knowledgeable friend.
