# Avenkin 2026.10 submission preparation

Prepared on 25 October 2026. App Store Connect app ID: 6760953562.

## Saved in App Store Connect

- Version 2026.10, subtitle, promotional text, description, keywords and review notes from `metadata.json`.
- Utilities primary category; Productivity secondary category.
- Support and privacy URLs use the current `avenkin.com` pages. Optional marketing URL is blank because the existing about page still promotes glasses and says there is no subscription.
- Content Rights declaration updated following the owner's confirmation. Imported manuals are user-provided; no manufacturer workshop PDFs are included.
- Mainland China excluded from distribution. France was already excluded and remains so; 173 territories are selected.
- Manual release retained. No build selected and nothing submitted for review.
- `avenkin-review-kit.zip` attached to App Review, containing two original fictional Markdown manuals and instructions.
- My Manuals monthly subscription review notes updated. Personal and Field Assist remain separate subscriptions.

## Uploaded screenshots

All uploads were verified by filename and count in App Store Connect. RGB PNGs have no alpha channel; UI pixels were not redesigned, stretched or composited.

| Device set | Uploaded assets | Dimensions |
| --- | --- | --- |
| iPhone medium Dynamic Island | Home, Apple app integrations, AI provider selection | 1206 × 2622 |
| iPad 13-inch | Workspace, Apple app integrations | 2752 × 2064 |
| Apple Watch Series 12 46mm | Connected companion controls | 416 × 496 |

The upload sources are `screenshots/*-rgb.png`. Captures use a Debug simulator with the shipping App Store glasses policy explicitly selected; this does not grant subscriptions or fabricate provider responses. Apple Intelligence is shown as the configured model, without claiming a successful AI request on the simulator.

## Remaining before submission

1. Merge the implementation PR when ready, let Xcode Cloud build it, then select the processed release build. Verify the App Store installation follows Plan JE and hides glasses functionality. The runtime distinction intentionally retains glasses support in TestFlight.
2. Retest the live My Manuals StoreKit catalogue after Apple's agreement/account changes propagate. Verify the displayed monthly price, eligible one-week trial, purchase, restore and separate service access. Capture the actual functioning paywall for the subscription's required review screenshot. Local StoreKit tests do not establish live catalogue availability.
3. Review and publish the saved App Privacy draft. It conservatively includes Health, Fitness, precise/coarse location, Contacts, photos/videos, audio, other user content and search history, used for App Functionality, linked to identity and not for tracking. The draft reflects optional third-party processing and has not been published or independently audited against every provider's retention practices. Reference: https://developer.apple.com/app-store/app-privacy-details/
4. Complete the final age-rating questionnaire audit and encryption questions for the selected build. Existing age rating was retained; no unverified accessibility claims were added.
5. An optional Duo screenshot remains outstanding. Device Hub accepted app launch and exposed posture controls, but repeatedly lost its window/remote accessibility connection and did not produce a verified expanded-screen capture. Do not claim physical folding has been tested. Existing iPhone/iPad assets must not be resized into a Duo screenshot.

## Source polish and validation

The App Store settings hub now hides Display & HUD and removes glasses wording from its device subtitle and About footer when the existing glasses policy is disabled. Debug simulator launch support can select this policy and an initial tab for repeatable captures; Release and physical-device channel detection are unchanged.

The final iOS simulator build succeeded (`/private/tmp/avenkin-store-settings-build.log`). The additional settings presentation changes were compile-checked; live purchase acceptance remains outstanding. Unrelated working-tree changes and private Toyota PDFs were not included in this preparation.
