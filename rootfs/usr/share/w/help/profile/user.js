// W Linux — the Help window's profile (w-help). Copied over the profile on every
// launch: edits here are W's; a user who wants other prefs sets them in about:config,
// which writes prefs.js (user.js only re-asserts the prefs listed below).

// chrome/userChrome.css (hidden chrome) and chrome/userContent.css (w-style axis
// `help` — the current theme over the site's variables).
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// One window, one tab: a second `w-help <page>` is a remote URL load into the
// running instance and lands in the current tab instead of a new one.
user_pref("browser.link.open_newwindow.override.external", 1);
user_pref("browser.tabs.warnOnClose", false);

// It is a viewer, not a browser: no first-run pages, no session restore, no
// default-browser nag. The page to open always comes from the command line.
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.startup.page", 0);
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("browser.tabs.inTitlebar", 0);

// A profile outside ~/.mozilla keeps its disk cache INSIDE the profile, i.e. in
// home and in every home snapshot; local files gain nothing from it.
user_pref("browser.cache.disk.enable", false);
