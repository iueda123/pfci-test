package dev.continuousimprovement.dispatcher.agent;
import dev.continuousimprovement.core.model.AgentResult;
public record AgentExecution(int exitCode,boolean timedOut,String auditOutput,AgentResult result) {}
