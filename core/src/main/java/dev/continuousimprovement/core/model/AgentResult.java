package dev.continuousimprovement.core.model;

import java.util.List;

public record AgentResult(
        Outcome outcome,
        String summary,
        List<TestResult> tests,
        List<String> filesChanged,
        List<String> risks,
        List<String> questions
) {
    public AgentResult {
        if (outcome == null) throw new IllegalArgumentException("outcome is required");
        if (summary == null || summary.isBlank()) throw new IllegalArgumentException("summary is required");
        tests = tests == null ? List.of() : List.copyOf(tests);
        filesChanged = filesChanged == null ? List.of() : List.copyOf(filesChanged);
        risks = risks == null ? List.of() : List.copyOf(risks);
        questions = questions == null ? List.of() : List.copyOf(questions);
    }

    public enum Outcome {
        CHANGED, NEEDS_INFO, NO_CHANGE, FAILED;
        @com.fasterxml.jackson.annotation.JsonValue public String json() { return name().toLowerCase(); }
        @com.fasterxml.jackson.annotation.JsonCreator public static Outcome parse(String value) { return valueOf(value.toUpperCase()); }
    }

    public record TestResult(String command, String result) {
    }
}
