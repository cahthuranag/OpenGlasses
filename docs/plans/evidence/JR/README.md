# Plan JR simulator evidence

Synthetic Workiz fixtures only, on iPhone 17 Pro / iOS 27.0. The key exists only in memory;
no account, customer data or live Workiz request was used. These are unmodified simulator PNGs,
for development review. AX5 is the largest Dynamic Type setting.

The fixture walks run the accessibility audit on every captured viewport. Existing app-wide
Form/secondary-colour and tab-bar deferrals remain. Default-size native Form clipping predictions
are narrowly deferred for the remove-key control and unidentified native nodes on the technician
and write-back settings viewports. The same controls pass the clipping check **without that
extra deferral at AX5**; the corresponding screenshots show the wrapped text. The existing
UIKit search field's single-line scrolling text is also narrowly deferred by its reported
`UISearchBarTextField` class on the Jobs list. The started job's existing single-line job-number
entry has the same native-text-entry exception. Clipping checks remain active for job rows,
briefs and visit delivery text. Visit screenshots wait for a stable frame after navigation.

The Workiz status scrolls with the Jobs list so it cannot consume the list's viewport at AX5.
The offline-status and assigned-jobs captures show both parts of that scroll.

| Viewport | Light | Dark | Light AX5 | Dark AX5 |
|---|---|---|---|---|
| Empty connection | [View](jr-settings-empty-light-default.png) | [View](jr-settings-empty-dark-default.png) | [View](jr-settings-empty-light-ax5.png) | [View](jr-settings-empty-dark-ax5.png) |
| Testing | [View](jr-settings-testing-light-default.png) | [View](jr-settings-testing-dark-default.png) | [View](jr-settings-testing-light-ax5.png) | [View](jr-settings-testing-dark-ax5.png) |
| Connected | [View](jr-settings-connected-light-default.png) | [View](jr-settings-connected-dark-default.png) | [View](jr-settings-connected-light-ax5.png) | [View](jr-settings-connected-dark-ax5.png) |
| Wrong key | [View](jr-settings-wrong-key-light-default.png) | [View](jr-settings-wrong-key-dark-default.png) | [View](jr-settings-wrong-key-light-ax5.png) | [View](jr-settings-wrong-key-dark-ax5.png) |
| Missing permission | [View](jr-settings-permission-light-default.png) | [View](jr-settings-permission-dark-default.png) | [View](jr-settings-permission-light-ax5.png) | [View](jr-settings-permission-dark-ax5.png) |
| Technician choice | [View](jr-technician-light-default.png) | [View](jr-technician-dark-default.png) | [View](jr-technician-light-ax5.png) | [View](jr-technician-dark-ax5.png) |
| Write-back settings | [View](jr-writeback-light-default.png) | [View](jr-writeback-dark-default.png) | [View](jr-writeback-light-ax5.png) | [View](jr-writeback-dark-ax5.png) |
| Offline status and cancellation | [View](jr-jobs-offline-light-default.png) | [View](jr-jobs-offline-dark-default.png) | [View](jr-jobs-offline-light-ax5.png) | [View](jr-jobs-offline-dark-ax5.png) |
| Assigned jobs | [View](jr-assigned-jobs-light-default.png) | [View](jr-assigned-jobs-dark-default.png) | [View](jr-assigned-jobs-light-ax5.png) | [View](jr-assigned-jobs-dark-ax5.png) |
| Job brief | [View](jr-brief-light-default.png) | [View](jr-brief-dark-default.png) | [View](jr-brief-light-ax5.png) | [View](jr-brief-dark-ax5.png) |
| Customer call | [View](jr-contact-light-default.png) | [View](jr-contact-dark-default.png) | [View](jr-contact-light-ax5.png) | [View](jr-contact-dark-ax5.png) |
| Started visit | [View](jr-started-light-default.png) | [View](jr-started-dark-default.png) | [View](jr-started-light-ax5.png) | [View](jr-started-dark-ax5.png) |
| Report sent | [View](jr-closed-sent-light-default.png) | [View](jr-closed-sent-dark-default.png) | [View](jr-closed-sent-light-ax5.png) | [View](jr-closed-sent-dark-ax5.png) |
| Report waiting | [View](jr-closed-waiting-light-default.png) | [View](jr-closed-waiting-dark-default.png) | [View](jr-closed-waiting-light-ax5.png) | [View](jr-closed-waiting-dark-ax5.png) |
| Report needs attention | [View](jr-closed-attention-light-default.png) | [View](jr-closed-attention-dark-default.png) | [View](jr-closed-attention-light-ax5.png) | [View](jr-closed-attention-dark-ax5.png) |

Live account qualification and the tester week remain deferred; see [Plan JR](../../JR-workiz-from-the-phone.md).
