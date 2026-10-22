# Avenkin: adaptive iPhone and iPad workspace

Design and implementation notes, 22 October 2026. The native SwiftUI app now uses an adaptive workspace. The open-Duo pane width has been checked in the native simulator; the full fold and multitasking workflows still need device validation.

## Implemented workspace

The existing Voice tab keeps its status, configurable action dock, conversation page, and Talk/Stop control. When the usable window fits a 340-point primary column and a 280-point context column, it adds context beside those controls. These minimums scale with text size; accessibility text uses a single column. This includes normal iPhone landscape as well as larger iPad windows. The dock's selected page and typed composer stay in the same view hierarchy during resizing.

Field Assist context reuses the existing Job tab with Job, Reference, and Evidence selectors. The evidence selector scrolls the existing job page to its photos and clips. Job timers, evidence choices, close-job review, and customer sign-off continue to use the existing services and flows. Outside Field Assist, context shows My Day when placed on Home, or the current conversation.

Manual citations open in the context column when available and in the existing sheet otherwise. The root owns their source selection and page controllers, preserving the reading position when a sheet becomes a pane or a pane becomes a sheet. Showing a reference never marks it verified.

The root uses SwiftUI's native sidebar-adaptable tab presentation. Native safe areas and system navigation determine bar placement; there is no guessed hinge position or separate session engine for a device pose.

With Xcode 27.2 and iOS 27.1 or later, the workspace queries active division reserved regions and their margins. In a book arrangement the panes stay on opposite sides of that division. With a horizontal division, the job/reference pane goes above it and the control surface goes below. If either usable region is too small, or accessibility text needs more room, context collapses and controls stay within the larger usable region. The same custom layout container places the existing views throughout these changes, preserving their identities. Older toolchains and runtimes retain ordinary window-size adaptation.

Short control surfaces use a compact session status button, including wake-phrase and camera state, with the full connection controls available in a sheet. Taller Field Assist workspaces show the shared conversation above the dock beside the job/reference pane.

The app delegate now accepts the orientations declared in Info.plist. Its previous portrait-only mask prevented a normal iPhone from reaching the landscape workspace even though the layout itself supported it.

The shared context pane uses local horizontal scroll-content margins. This prevents embedded job and evidence lists from reserving the outer vertical navigation rail's trailing margin again, which left their cards narrower than the pane on an open Duo. Reference uses the same full-width context boundary.

Xcode 27.2 validates generated project groups more strictly. `createIntermediateGroups` keeps shared source files in one complete group hierarchy, avoiding duplicate group parents without changing target membership.

## Shared experience

Keep Avenkin, Modes, History, and Settings in the existing order. Preserve the current conditional Field Assist and Job destinations, entitlement rules, and organisation restrictions. The consumer preview omits those conditional destinations.

Keep the active conversation, selected assistant, draft, audio state, and selected day item when the window changes size or the device folds. Camera access and device pairing remain optional; the phone audio experience works independently.

Use Avenkin's warm accent, system typography, quiet content surfaces, and system materials for navigation. Content leads; navigation and voice controls stay easy to reach.

## Layouts

| Context | Content | Navigation and controls |
| --- | --- | --- |
| Duo outer display | One conversation or My Day detail at a time. Preserve the conversation when showing the day. | Native vertical bars at the outer edge. Keep message entry and the prominent voice action within the content safe area. |
| Duo inner display, wide | Conversation leading; My Day or the currently selected reference trailing. | Native vertical toolbars and tabs. Let the system choose their edge in multitasking. |
| Duo inner display, portrait | Same hierarchy, with content adapting to available space. | Native horizontal bars where the system supplies them. |
| Duo tabletop, optional enhancement | Job or reference above; conversation, message entry, and voice controls on the stable lower region. | Native bars and reserved-region layout. No feature is exclusive to this pose. |
| iPad, ample space | Leading app sidebar; central conversation; optional trailing My Day or contextual reference. | Native sidebar and contextual toolbar. |
| Narrow iPad window or multitasking | Hide the contextual column first; collapse navigation when necessary. Open context through the same navigation hierarchy. | Use the space available to the scene. Preserve focus, draft, and selection. |

These are design presentations, not fixed device breakpoints. Choose native adaptive containers using size classes and current view geometry. Do not infer layout from device names, idiom, orientation, or physical screen pixels. For accessibility text sizes, allow the context column to collapse into a navigable detail rather than compressing the text.

## Native implementation direction

- Replace the root's forced `.tabBarOnly` presentation with an appropriate adaptive native tab/sidebar presentation. Keep the existing selection and entitlement policies authoritative.
- Compose the existing Voice, My Day, conversation, and context views into an adaptive split presentation. Use a readable conversation width and flexible spacing rather than stretching messages across the display.
- Use native toolbars, sheets, alerts, and menus for system positioning and fold avoidance. The preview rail illustrates placement; do not implement it as a hardcoded right-edge overlay.
- Respect horizontal safe areas, layout margins, and the system's reserved regions. Derive optional tabletop arrangements from those regions, not a guessed hinge coordinate.
- Keep session and conversation ownership above layout branches. Resizing must not create a new SDK stream or restart audio. Paused sessions remain paused until the SDK resumes or stops them.
- Support Dynamic Type, VoiceOver reading order, keyboard navigation, Reduce Motion, and right-to-left layout. Keep controls at least 44 points in their native touch presentation.

## Validation before shipping

Xcode 27.2 validation passed 119 focused unit tests covering layout and division placement, dock paging, job models, manual citations, and reading-position retention. Native iPhone UI checks passed for conversation/dock retention on rotation, unsent drafts in both landscape directions, and Field Assist pane width plus visible evidence controls and Evidence selection after rotation. The privacy-logging gate also passed.

A signed layout build was installed and launched on GiPhone with its normal settings and existing data. Native open-Duo before/after screenshots confirmed that job cards fill the context pane with local margins. A physical iPad, actual side-by-side multitasking placements, and live voice/camera continuity through folds or window resizing have not been verified.

Use Xcode 27.2's Duo simulator and Device Hub for the full native behavior. Exercise both displays, both orientations, partial folds, tabletop use, left and right multitasking placements, short windows, keyboard presentation, large accessibility text, and foreground/background transitions. Verify navigation, drafts, scroll position, and an active voice/stream session survive each transition.

The interactive design preview was checked separately in a browser. It cannot validate SDK behavior, system bar relocation, fold avoidance, or simulator rendering.

## Apple references

- [Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/): compact/regular adaptation, control placement, continuity, and system fold avoidance.
- [Strike a pose with adaptive layouts on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111463/): reserved regions and optional content/control arrangements.
- [Three steps to make your app shine on iPhone Duo](https://developer.apple.com/iphone-duo/prepare/): build SDK behavior, geometry assumptions, and resizing validation.
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout): iPad window resizing and collapsing secondary content.
- [Apple Design Resources](https://developer.apple.com/design/resources/): platform templates and design kits.
