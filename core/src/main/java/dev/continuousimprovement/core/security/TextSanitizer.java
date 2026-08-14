package dev.continuousimprovement.core.security;

import java.util.regex.Pattern;

public final class TextSanitizer {
    private static final Pattern CONTROL = Pattern.compile("[\\p{Cc}&&[^\\r\\n\\t]]");
    private static final Pattern NEWLINES = Pattern.compile("\\R+");

    private TextSanitizer() {
    }

    public static String reporterName(String value) {
        if (value == null || value.isBlank()) return null;
        var result = singleLine(value, 50);
        while (result.startsWith("@")) result = result.substring(1).stripLeading();
        return result.isBlank() ? null : result;
    }

    public static String requiredSingleLine(String value, String field, int max) {
        var result = optionalSingleLine(value, max);
        if (result == null || result.isBlank()) throw new IllegalArgumentException(field + " is required");
        return result;
    }

    public static String optionalSingleLine(String value, int max) {
        if (value == null || value.isBlank()) return null;
        return singleLine(value, max);
    }

    public static String requiredMultiline(String value, String field, int max) {
        var result = optionalMultiline(value, max);
        if (result == null || result.isBlank()) throw new IllegalArgumentException(field + " is required");
        return result;
    }

    public static String optionalMultiline(String value, int max) {
        if (value == null || value.isBlank()) return null;
        var result = CONTROL.matcher(value).replaceAll("").replace("\r\n", "\n").replace('\r', '\n').strip();
        if (result.length() > max) throw new IllegalArgumentException("value exceeds " + max + " characters");
        return result;
    }

    private static String singleLine(String value, int max) {
        var noControl = CONTROL.matcher(value).replaceAll("");
        var result = NEWLINES.matcher(noControl).replaceAll(" ").strip();
        if (result.length() > max) throw new IllegalArgumentException("value exceeds " + max + " characters");
        return result;
    }
}
