package dev.continuousimprovement.core.security;

import java.util.Map;

public record RedactionResult(String value, Map<String, Integer> replacements, String ruleVersion) {
    public RedactionResult {
        replacements = Map.copyOf(replacements);
    }

    public int replacementCount() {
        return replacements.values().stream().mapToInt(Integer::intValue).sum();
    }
}
