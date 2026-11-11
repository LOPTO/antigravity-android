package com.agy.ui;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.os.LocaleList;

import java.util.Locale;

/** Stores the interface language shared by the host and its WebView. */
public final class UiLanguage {
    private static final String PREFS = "agy_prefs";
    private static final String KEY = "ui_language";
    private static final String CHINESE = "zh-CN";
    private static final String ENGLISH = "en";

    private UiLanguage() {}

    public static String current(Context context) {
        String saved = preferences(context).getString(KEY, CHINESE);
        return ENGLISH.equals(saved) ? ENGLISH : CHINESE;
    }

    static boolean select(Context context, String language) {
        if ((!CHINESE.equals(language) && !ENGLISH.equals(language))
                || language.equals(current(context))) {
            return false;
        }
        preferences(context).edit().putString(KEY, language).apply();
        return true;
    }

    public static Context localized(Context context) {
        Configuration override = new Configuration();
        override.setLocales(new LocaleList(Locale.forLanguageTag(current(context))));
        return context.createConfigurationContext(override);
    }

    public static String text(Context context, int id) {
        return localized(context).getString(id);
    }

    public static String text(Context context, int id, Object... args) {
        return localized(context).getString(id, args);
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }
}
