package dev.continuousimprovement.core.model;

import java.util.Locale;
import java.util.Objects;

public record EnvironmentInfo(
        String os,
        String osVersion,
        String architecture,
        String jdk,
        String javafx,
        String locale,
        String screenId,
        String displayServer
) {
    public EnvironmentInfo {
        os = required(os, "os", 100);
        osVersion = normalized(osVersion, 100);
        architecture = normalized(architecture, 50);
        jdk = required(jdk, "jdk", 100);
        javafx = required(javafx, "javafx", 100);
        locale = normalized(locale, 50);
        screenId = required(screenId, "screenId", 100);
        displayServer = normalized(displayServer, 50);
    }

    public static EnvironmentInfo current(String screenId) {
        var display = System.getenv("XDG_SESSION_TYPE");
        return new EnvironmentInfo(
                System.getProperty("os.name"),
                System.getProperty("os.version"),
                System.getProperty("os.arch"),
                System.getProperty("java.version"),
                System.getProperty("javafx.version", "unknown"),
                Locale.getDefault().toLanguageTag(),
                screenId,
                display == null ? "unknown" : display
        );
    }

    private static String required(String value, String name, int max) {
        var normalized = normalized(value, max);
        if (normalized == null || normalized.isBlank()) {
            throw new IllegalArgumentException(name + " is required");
        }
        return normalized;
    }

    private static String normalized(String value, int max) {
        if (value == null) return null;
        var result = Objects.requireNonNull(value).strip();
        if (result.length() > max) throw new IllegalArgumentException("value is too long");
        return result;
    }
}
