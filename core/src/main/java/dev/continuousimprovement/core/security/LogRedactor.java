package dev.continuousimprovement.core.security;

import dev.continuousimprovement.core.model.LogEvent;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

public final class LogRedactor {
    public static final String RULE_VERSION = "2026-08-11.1";

    private static final List<Rule> RULES = List.of(
            new Rule("AUTH_HEADER", Pattern.compile("(?i)(authorization\\s*[:=]\\s*)(?:bearer\\s+)?[^\\s,;]+"), "$1[REDACTED:AUTH_HEADER]"),
            new Rule("COOKIE", Pattern.compile("(?i)((?:set-)?cookie\\s*[:=]\\s*)[^\\r\\n]+"), "$1[REDACTED:COOKIE]"),
            new Rule("JWT", Pattern.compile("(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])"), "[REDACTED:JWT]"),
            new Rule("SECRET", Pattern.compile("(?i)(\\b(?:password|passwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token)\\b\\s*[:=]\\s*)[^\\s,;]+"), "$1[REDACTED:SECRET]"),
            new Rule("SESSION_ID", Pattern.compile("(?i)(\\b(?:session[_-]?id|jsessionid)\\b\\s*[:=]\\s*)[^\\s,;]+"), "$1[REDACTED:SESSION_ID]"),
            new Rule("CONNECTION_STRING", Pattern.compile("(?i)\\b(?:postgres(?:ql)?|mysql|mongodb(?:\\+srv)?)://[^\\s]+"), "[REDACTED:CONNECTION_STRING]"),
            new Rule("API_TOKEN", Pattern.compile("\\b(?:gh[opsu]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,})\\b"), "[REDACTED:API_TOKEN]"),
            new Rule("EMAIL", Pattern.compile("(?i)\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b"), "[REDACTED:EMAIL]"),
            new Rule("HOME_PATH", Pattern.compile("(?<![A-Za-z0-9_])/(?:home|Users)/[^/\\s]+"), "/[REDACTED:HOME]")
    );

    public RedactionResult redact(String input) {
        var value = input == null ? "" : input.replaceAll("[\\r\\n]+", " ");
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (var rule : RULES) {
            var matcher = rule.pattern.matcher(value);
            int count = 0;
            while (matcher.find()) count++;
            if (count > 0) {
                value = rule.pattern.matcher(value).replaceAll(rule.replacement);
                counts.put(rule.name, count);
            }
        }
        return new RedactionResult(value, counts, RULE_VERSION);
    }

    public LogEvent redact(LogEvent event) {
        return new LogEvent(
                event.timestamp(),
                safe(event.level()),
                safe(event.logger()),
                safe(event.thread()),
                redact(event.message()).value(),
                redact(event.throwable()).value(),
                redact(event.correlationId()).value()
        );
    }

    private String safe(String value) {
        return redact(value == null ? "" : value.toLowerCase(Locale.ROOT)).value();
    }

    private record Rule(String name, Pattern pattern, String replacement) {
    }
}
