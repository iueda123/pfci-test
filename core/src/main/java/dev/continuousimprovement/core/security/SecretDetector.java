package dev.continuousimprovement.core.security;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

public final class SecretDetector {
    private static final List<NamedPattern> PATTERNS = List.of(
            new NamedPattern("private-key", Pattern.compile("-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
            new NamedPattern("github-token", Pattern.compile("\\b(?:ghp|github_pat)_[A-Za-z0-9_]{20,}\\b")),
            new NamedPattern("openai-key", Pattern.compile("\\bsk-[A-Za-z0-9_-]{20,}\\b")),
            new NamedPattern("jwt", Pattern.compile("\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b")),
            new NamedPattern("signed-url", Pattern.compile("(?i)(?:token|signature|sig)=[A-Za-z0-9%._~-]{12,}"))
    );

    public List<String> detect(String value) {
        List<String> findings = new ArrayList<>();
        if (value == null) return findings;
        for (var item : PATTERNS) {
            if (item.pattern.matcher(value).find()) findings.add(item.name);
        }
        return List.copyOf(findings);
    }

    private record NamedPattern(String name, Pattern pattern) {
    }
}
