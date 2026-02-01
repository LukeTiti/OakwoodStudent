# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Oakwood Students App is an iOS application providing an enhanced student portal for Oakwood School with grade tracking, assignment management, sports schedules, and news feeds. Built with SwiftUI.

## Build Commands

This is an Xcode project. Open and build with:
```bash
open "Oakwood Students App/School Notes.xcodeproj"
```

Build from command line:
```bash
xcodebuild -project "Oakwood Students App/School Notes.xcodeproj" -scheme "School Notes" -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Run tests:
```bash
xcodebuild -project "Oakwood Students App/School Notes.xcodeproj" -scheme "School Notes" -destination 'platform=iOS Simulator,name=iPhone 15' test
```

## Architecture

### App Structure
- **Entry Point:** `School_NotesApp.swift` - Initializes Google Sign-In and sets up environment
- **Main Navigation:** `ContentView.swift` - TabView with 5 active tabs (Inside Scoop, To Do, Grades, Sports, Service)
- **State Management:** `Observable Class.swift` - `AppInfo` ObservableObject singleton manages global state and persistence

### Key Views and Data Flow

| View | File | Data Source |
|------|------|-------------|
| Inside Scoop (News) | `Home Page.swift` | Scrapes oakwoodway.org via SwiftSoup |
| Grades | `Veracross.swift` | Veracross portal API (requires WebView login) |
| To Do | `ToDoPage.swift` | Uses assignments from AppInfo.courses |
| Sports | `Sports View.swift` | Fetches from GitHub Sport-Data-Branch |
| Service | `Community Service.swift` | Local tracking (minimal implementation) |

### External APIs

1. **Veracross Portal** - School grades system
   - WebView login at `portals.veracross.com/oakwood/student`
   - JSON APIs for course list and assignments
   - Session maintained via dual cookie stores (HTTPCookieStorage + WKWebsiteDataStore)

2. **Oakwood Website** - News scraping from oakwoodway.org/inside-scoop

3. **GitHub Raw** - Sports data from Sport-Data-Branch

### Data Persistence

All persistence uses UserDefaults:
- `assignmentInfo` - Assignment completion status (Dictionary<Int, Bool>)
- `persistedCookies` - Veracross session cookies
- Google Sign-In state (isSignedIn, userName, userEmail)

### Dependencies

- **GoogleSignIn** - OAuth authentication
- **SwiftSoup** - HTML parsing
- **WebKit** - WKWebView for Veracross login

## Key Patterns

- Views observe `AppInfo` via `@EnvironmentObject`
- Async/await for all network calls
- Cookie sync between HTTPCookieStorage and WKWebsiteDataStore required for Veracross session persistence
