// W Linux — Quickshell greeter shell root.
// A separate, deliberately MINIMAL Quickshell config used only by the login
// manager (greetd backend). It mounts a single component — the login screen —
// and nothing else: no bar, launcher, power menu, tray or global shortcuts. The
// greeter does exactly one thing: authenticate a user. Colors/Motion/Fonts come
// from the same JSON contract as the user shell, rendered here by
// `w-style apply greeter` (system scope) from the active system theme.
import Quickshell
import qs.modules.greeter

ShellRoot {
    Greeter {}
}
