package app.chatterkey.android;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.WindowManager;

public final class SettingsActivity extends Activity {
    private SettingsView screen;

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        screen = new SettingsView(this);
        screen.createContent(
                new SettingsStore(this),
                new UsageStore(this),
                () -> requestPermissions(new String[] {Manifest.permission.RECORD_AUDIO}, 1));
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            screen.setOnApplyWindowInsetsListener(
                    (view, insets) -> {
                        android.graphics.Insets safe =
                                insets.getInsets(
                                        android.view.WindowInsets.Type.systemBars()
                                                | android.view.WindowInsets.Type.displayCutout()
                                                | android.view.WindowInsets.Type.ime());
                        view.setPadding(safe.left, safe.top, safe.right, safe.bottom);
                        return insets;
                    });
        } else screen.setFitsSystemWindows(true);
        setContentView(screen);
        if (state != null) {
            screen.period = Math.max(0, Math.min(2, state.getInt("period", 0)));
            screen.selectTab(Math.max(0, Math.min(2, state.getInt("tab", 0))));
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(requestCode, permissions, results);
        if (requestCode != 1 || results.length == 0) return;
        if (results[0] != PackageManager.PERMISSION_GRANTED) {
            new AlertDialog.Builder(this)
                    .setTitle("Microphone permission")
                    .setMessage(
                            "Typing still works without microphone access. To enable voice, allow"
                                + " Microphone in this app's system permissions. If Android no"
                                + " longer shows the permission prompt, use Open app settings"
                                + " below.")
                    .setNegativeButton("Not now", null)
                    .setPositiveButton(
                            "Open app settings",
                            (dialog, which) ->
                                    startActivity(
                                            new Intent(
                                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                                    Uri.fromParts(
                                                            "package", getPackageName(), null))))
                    .show();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (screen != null) screen.refreshUsage();
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        state.putInt("tab", screen.selectedTab);
        state.putInt("period", screen.period);
        super.onSaveInstanceState(state);
    }
}
