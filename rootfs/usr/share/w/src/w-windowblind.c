#include <gtk/gtk.h>
#include <gtk4-layer-shell.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// Fullscreen blind shown for <ms> milliseconds, then quits.
//   w-windowblind <ms> <#color>           solid color (session fade-in/out)
//   w-windowblind <ms> --image <path>     one freeze-frame image on every output
//   w-windowblind <ms> --image-dir <dir>  per-output freeze: <dir>/<connector>.png
//   ... --ready-fifo <path>               optional, any mode: write one byte to
//                                         <path> once every surface has been
//                                         gtk_window_present()-ed. Lets a caller
//                                         (w-theme) wait for the actual mapping
//                                         instead of guessing a process-startup
//                                         delay — GTK4/layer-shell init time is
//                                         variable (dynamic linking, cold cache),
//                                         so a fixed sleep from launch time can
//                                         fire before the surface is even up.
//
// Rendered as a layer-shell OVERLAY surface (like hyprlock): it sits above all
// windows without ever touching the tiling layout, so existing windows never
// jump. Hyprland layer fade animations (layerrule, namespace w-windowblind)
// drive the in/out fade.
//
// ONE SURFACE PER OUTPUT. The layer-shell default output is NULL, which lets the
// compositor pick a single one — on a multi-monitor session that leaves the other
// screens uncovered, so every window is pinned with gtk_layer_set_monitor().
// All of them live in this one process and map in the same frame, so the fade
// plays in sync on every screen and killing the process fades them out together.
//
// --image-dir keys each capture by connector name (eDP-1, DP-3 …). That is the
// wl_output name — the same name `hyprctl monitors` reports and `grim -o`
// accepts — so the mapping needs no translation. A single canvas-wide capture
// cannot be reused per output: it stitches all outputs into one image, which a
// single-output surface can only crop wrongly (half of one screen plus half of
// the next), which is exactly what this mode replaces.
typedef struct {
    int ms;
    const char *color;
    const char *image;
    const char *image_dir;
    const char *ready_fifo;
} Config;

// One overlay surface pinned to `mon`. image == NULL → the display-wide CSS
// provider (solid color mode) paints the window background instead.
static void add_blind(GtkApplication *app, GdkMonitor *mon, const char *image) {
    GtkWidget *win = gtk_application_window_new(app);
    gtk_application_window_set_show_menubar(GTK_APPLICATION_WINDOW(win), FALSE);

    // Layer-shell overlay, anchored to all edges → stretches across the whole
    // output, above everything, ignoring exclusive zones (bars). No keyboard
    // grab: the blind is purely visual and short-lived.
    gtk_layer_init_for_window(GTK_WINDOW(win));
    gtk_layer_set_namespace(GTK_WINDOW(win), "w-windowblind");
    gtk_layer_set_layer(GTK_WINDOW(win), GTK_LAYER_SHELL_LAYER_OVERLAY);
    gtk_layer_set_monitor(GTK_WINDOW(win), mon);
    gtk_layer_set_anchor(GTK_WINDOW(win), GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_anchor(GTK_WINDOW(win), GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
    gtk_layer_set_anchor(GTK_WINDOW(win), GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_anchor(GTK_WINDOW(win), GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    gtk_layer_set_exclusive_zone(GTK_WINDOW(win), -1);

    if (image) {
        // Cover the window with the captured frame (preserves aspect, fills).
        // With a per-output capture the aspect already matches exactly; COVER
        // keeps a mismatched frame from stretching if one ever slips through.
        GtkWidget *pic = gtk_picture_new_for_filename(image);
        gtk_picture_set_content_fit(GTK_PICTURE(pic), GTK_CONTENT_FIT_COVER);
        gtk_widget_set_hexpand(pic, TRUE);
        gtk_widget_set_vexpand(pic, TRUE);
        gtk_window_set_child(GTK_WINDOW(win), pic);
    }

    gtk_window_set_decorated(GTK_WINDOW(win), FALSE);
    gtk_window_present(GTK_WINDOW(win));
}

static void activate(GtkApplication *app, gpointer data) {
    Config *cfg = data;

    if (cfg->color) {
        char css[64];
        snprintf(css, sizeof(css), "window { background-color: %s; }", cfg->color);
        GtkCssProvider *provider = gtk_css_provider_new();
        gtk_css_provider_load_from_string(provider, css);
        gtk_style_context_add_provider_for_display(
            gdk_display_get_default(),
            GTK_STYLE_PROVIDER(provider),
            GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
        g_object_unref(provider);
    }

    GListModel *monitors = gdk_display_get_monitors(gdk_display_get_default());
    guint n = g_list_model_get_n_items(monitors);
    guint shown = 0;

    for (guint i = 0; i < n; i++) {
        GdkMonitor *mon = g_list_model_get_item(monitors, i);
        const char *image = cfg->image;
        char *per_output = NULL;

        if (cfg->image_dir) {
            const char *connector = gdk_monitor_get_connector(mon);
            per_output = g_strdup_printf("%s/%s.png", cfg->image_dir, connector ? connector : "");
            if (connector && g_file_test(per_output, G_FILE_TEST_EXISTS)) {
                image = per_output;
            } else {
                // No capture for this output (hotplugged between capture and
                // launch, or a nameless connector). Leave it uncovered — that
                // only loses the freeze on this screen, whereas showing a
                // foreign frame or a black rectangle would be a visible glitch.
                fprintf(stderr, "w-windowblind: no freeze frame for output '%s', skipping\n",
                        connector ? connector : "?");
                g_free(per_output);
                g_object_unref(mon);
                continue;
            }
        }

        // gtk_picture_new_for_filename() copies the path, so freeing it here is safe.
        add_blind(app, mon, image);
        shown++;
        g_free(per_output);
        g_object_unref(mon);
    }

    // Every gtk_window_present() call above has been made — the toolkit has
    // asked the compositor to map each surface. Signal the caller now, before
    // deciding whether there was anything to show: a caller waiting on this
    // fifo should not block on a case where the blind has nothing to display.
    if (cfg->ready_fifo) {
        FILE *f = fopen(cfg->ready_fifo, "w");
        if (f) { fputc('1', f); fclose(f); }
    }

    if (shown == 0) {
        fprintf(stderr, "w-windowblind: no output to cover\n");
        g_application_quit(G_APPLICATION(app));
        return;
    }

    g_timeout_add(cfg->ms, (GSourceFunc)g_application_quit, app);
}

int main(int argc, char **argv) {
    Config cfg = { 0, NULL, NULL, NULL, NULL };
    int next = 0;

    if (argc >= 4 && strcmp(argv[2], "--image") == 0) {
        cfg.ms = atoi(argv[1]);
        cfg.image = argv[3];
        next = 4;
    } else if (argc >= 4 && strcmp(argv[2], "--image-dir") == 0) {
        cfg.ms = atoi(argv[1]);
        cfg.image_dir = argv[3];
        next = 4;
    } else if (argc >= 3) {
        cfg.ms = atoi(argv[1]);
        cfg.color = argv[2];
        next = 3;
    } else {
        fprintf(stderr, "Usage: w-windowblind <ms> <#color> [--ready-fifo <path>]\n"
                        "       w-windowblind <ms> --image <path> [--ready-fifo <path>]\n"
                        "       w-windowblind <ms> --image-dir <dir> [--ready-fifo <path>]   (<dir>/<connector>.png)\n");
        return 1;
    }

    for (int i = next; i + 1 < argc; i++) {
        if (strcmp(argv[i], "--ready-fifo") == 0) cfg.ready_fifo = argv[i + 1];
    }

    GtkApplication *app = gtk_application_new("w.windowblind", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), &cfg);
    int status = g_application_run(G_APPLICATION(app), 0, NULL);
    g_object_unref(app);
    return status;
}
