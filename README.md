# UniKM / Universal Key Manager
A cross-platform desktop application for organizing and managing your game product keys and activation codes. UniKM features Steam integration, encryption, and a themeable UI.
This is a complete rewrite of SteamKM2, using Dart language and Flutter as the front-end.

![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.41.2%2B-02569B?logo=flutter)
![Version](https://img.shields.io/badge/Version-1.1.0-purple)
![License](https://img.shields.io/badge/License-GPL--3.0-blue)


## Overview

UniKM keeps all your game keys in one place: organized, searchable, and secure. Whether you have a handful of codes or hundreds from Humble Bundle, Fanatical, Green Man Gaming bundles or from some other place, UniKM gives you a place to store them efficiently. It integrates directly with Steam to enrich your library with cover art, ratings, and tags automatically, and optionally encrypts your database so your keys stay private.

## Features

### Game Library Management
- Add, edit, and delete game entries with title, key, status (used/unused), notes, and tags
- Right-click context menu for quick actions: copy key, mark used/unused, fetch Steam data, delete
- Mark games as used or unused with visual indicators
- Attach expiry/deadline dates with automatic reminder notifications

### Steam Integration
- Search the Steam store and auto-fill game details with a single click
- Batch-fetch cover images, ratings, and release dates for multiple games at once
- Sync tags directly from SteamSpy for automated genre/category labeling
- Intelligent fuzzy title matching to find the correct Steam entry even with slight name differences

### Tagging & Organization
- Create custom tags
- Filter and sort your library by tags, title, status, or date
- Multi-select games for batch operations (delete, status change, Steam fetch)

### Search & Views
- Fast full-text search across your entire library
- Toggle between grid (cover art) and list view
- Cached Steam cover images for offline browsing

### Database Encryption
- AES-256-GCM encryption with PBKDF2 key derivation
- Prompt for your password on startup; nothing is stored in plaintext
- Enable or disable encryption at any time from Settings

### Multiple Databases & Backups
- Maintain separate databases for different collections (e.g., personal vs. gifts)
- Switch between databases with one click; recent databases are remembered
- Automatic scheduled backups with one-click restore

### Import & Export
- Import from CSV, JSON, or legacy SQLite databases (SteamKM2)
- Batch import multiple games from a file
- Export your full library to JSON or CSV

### Themes & Customization
- Built-in themes to get you started
- Custom theme editor with a three-color palette system for full personalization
- Animated gradient effects for the gradient bar

### Notifications
- OS-level desktop notifications (Windows, macOS, Linux)
- Deadline reminders: get notified before a key's expiry date
- Daily background checks for upcoming deadlines

### Built-in Updater
- Automatic update checking on launch
- In-app changelog viewer rendered from Markdown
- One-click download and install of the latest release
- Option to skip specific versions, updates are not forced onto the user

### Supported Platforms
| Platform | Status |
|----------|--------|
| Windows  | ✅ Fully supported |
| macOS    | ⚠️ Experimental |
| Linux    | ⚠️ Experimental |
| Android  | ⚠️ Experimental |
| iOS      | ⚠️ Experimental |


### Screenshots
<img width="2441" height="1402" alt="image" src="https://github.com/user-attachments/assets/71819ef7-7b58-423b-9ed2-8b3e0d9f7e30" />
<img width="2433" height="1396" alt="image" src="https://github.com/user-attachments/assets/9cd9aaa5-bd23-4404-9160-cdae990f3564" />

---

### Migrating from a Previous Version
From SteamKM1:
- SteamKM1 → SteamKM2: Export your library from SteamKM1 as a JSON file, then import it into SteamKM2 using the Import button on the Add Games page.
- SteamKM2 → UniKM: Once your data is in SteamKM2, open UniKM and use Menu (☰) → Import Database → Select Source file or Drag the file to the source file box. The SteamKM2 database must be unencrypted before importing.

From SteamKM2 to UniKM:
- Open UniKM and use Menu (☰) button on the title bar → Import Database → Select Source file or Drag the file to the source file box. UniKM will map all your entries to the new schema.

Direct migration from SteamKM1 to UniKM will be coming soon.
