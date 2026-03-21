# App Store Submission: Compliance and Release Checklist

## When to Activate

Use before first submission or any release that changes permissions, data collection, monetization, or significant UX—Apple App Store and Google Play.

## Process

1. **Privacy nutrition / data safety.** Map every SDK to data types collected; declare tracking (ATT on iOS 14+), analytics, and crash data. Align in-app disclosure with store forms (App Privacy, Play Data safety).
2. **Permission strings.** Every `Info.plist` usage description (`NSCameraUsageDescription`, etc.) must match real behavior. Android: dangerous permissions in manifest + runtime prompts only when needed.
3. **Screenshots and review notes.** Localize store assets; in review notes list test accounts, backend toggles, and feature flags. Provide a short video for complex flows.
4. **IAP and receipts.** Server-side validate Apple App Store Server API / Google Play Developer API receipts; never trust client-only unlocks. Handle subscription grace periods and refunds.
5. **Phased rollout.** Start Play staged rollout at 5–20%; use App Store phased release or manual pause. Monitor ANRs/crashes in Play Console and Xcode Organizer / third-party dashboards.
6. **Rejection patterns.** Guideline 2.1 (incomplete/broken), 4.0 (design), 5.1.1 (privacy), account login without demo credentials. Pre-verify metadata matches binary.

## Checklist

- [ ] Privacy labels match SDK and app behavior
- [ ] All permission copy audited against code paths
- [ ] Reviewer credentials and notes uploaded
- [ ] IAP/receipt validation path tested end-to-end
- [ ] Rollout plan + crash dashboard watchers assigned

## Tips

Keep a “store diff” doc per release: version, build, what changed for reviewers, and links to compliance policies. Re-run automated accessibility checks before capture of store screenshots.
