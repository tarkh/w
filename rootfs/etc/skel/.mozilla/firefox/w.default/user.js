// W Linux — Firefox profile prefs (apply.sh --firefox). user.js is re-applied to
// prefs.js on every startup, so these stay enforced. System-wide, authoritative
// policy lives in /etc/firefox/policies/policies.json; this file holds only what a
// policy cannot express (the userChrome opt-in) or what is profile-local UX.

// ── Theme: enable userChrome.css / userContent.css ────────────────────────────
// Required for the W transparency layer the `firefox` w-style axis renders into
// chrome/userChrome.css. NOT available as an enterprise policy, so it lives here.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// ── First-run / onboarding noise off (policies cover most; these are belt-and-
//    suspenders for a clean first launch) ──────────────────────────────────────
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.shell.checkDefaultBrowser", false);

// ── New-tab page: keep it clean (no sponsored shortcuts / Pocket stories) ─────
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);

// ── Privacy (conservative — deliberately NO resistFingerprinting / strict ETP,
//    which break site layouts and logins; those stay default) ──────────────────
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("browser.discovery.enabled", false);
