package dev.continuousimprovement.dispatcher.agent;
import java.nio.file.Path;import java.time.Duration;
public interface AgentAdapter { String name(); AgentExecution execute(Path worktree,Path evidence,String prompt,Path resultFile,Duration timeout) throws Exception; }
