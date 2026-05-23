---
id: youtube.search_and_save
title: Search and save a YouTube video
language_hints:
  uz: YouTube'da video qidiring va saqlang
  ru: Найдите и сохраните видео на YouTube
app:
  url_match: youtube.com
prerequisites:
  - You have an internet connection and a Google account
estimated_minutes: 3
sort_order: 19
suggested_next:
  - youtube.create_playlist
---

# Search and save a YouTube video

By the end of this lesson the learner has searched for a video on YouTube, opened it, liked it, and saved it to Watch Later. This teaches the basic loop of finding, evaluating, and bookmarking content — the skills needed to use YouTube as a learning tool, not just an entertainment scroll.

**Teaching stance:** YouTube is fun — let it be fun. Don't lecture about screen time. The goal is showing that YouTube has a search-and-save workflow, not just an endless feed.

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

## Step 2 — Go to YouTube

> Click the address bar and type "youtube.com" then press Return.

```yaml
expect:
  match:
    scope: app_window
    role: text_field
    any_of:
      - { identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" }
      - { label_contains: "Address" }
  advance_when: url_contains
  advance_value: youtube.com
```

## Step 3 — Search for a video

> Find the search box at the top of the YouTube page. Click it, type something you're interested in — "how to make pasta" or "learn guitar" — and press Return.

**Teach:** YouTube's search works like Google — type what you want to learn and it shows you videos ranked by relevance. You can also search for specific channels or topics.

```yaml
expect:
  match:
    any_of:
      - { role: searchbox, label_contains: "Search" }
      - { role: text_field, label_contains: "Search" }
      - { role: searchbox, label_contains: "Поиск" }
      - { role: searchbox, label_contains: "Qidirish" }
  advance_when: focused_element_changes
```

## Step 4 — Click a video

> You'll see a list of video results with thumbnails. Click on any video that looks interesting — the thumbnail or the title both work.

**Teach:** The number below each title shows how many people have watched it. Higher view counts usually mean the video is well-made, but smaller channels can be great too.

```yaml
expect:
  advance_when: url_contains
  advance_value: watch
```

## Step 5 — Like the video

> Below the video, you'll see a thumbs-up icon. Click it to like the video. The icon fills in to show your like was counted.

**Teach:** Liking helps YouTube learn what you enjoy, so it can recommend better videos. It also supports the creator who made it.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label_contains: "like" }
      - { label_contains: "Like" }
      - { label_contains: "Нравится" }
      - { label_contains: "Yoqdi" }
  advance_when: focused_element_changes
```

## Step 6 — Save to Watch Later

> Next to the like button, look for a "Save" button or three-dot menu. Click it and choose "Watch later" from the list.

**Teach:** Watch Later is your personal bookmark list. Any video you save here shows up in your Library tab on the left sidebar, so you can find it again without searching.

```yaml
expect:
  match:
    role: button
    any_of:
      - { label_contains: "Save" }
      - { label_contains: "Сохранить" }
      - { label_contains: "Saqlash" }
  advance_when: window_changes
  also_advance_when: focused_element_changes
```

## Wrap-up

> You found a video, liked it, and saved it for later. That's how you use YouTube intentionally — search for what you need, bookmark what's useful, and come back to it. Your Watch Later list is in the Library section on the left sidebar.
