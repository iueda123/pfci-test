package dev.continuousimprovement.dispatcher.agent;
/** The agent process finished but did not produce a usable result JSON. Carries the run output so the dispatcher can still persist a redacted audit record. */
public final class AgentResultFormatException extends Exception {
 private final int exitCode;private final String auditOutput;
 public AgentResultFormatException(String message,int exitCode,String auditOutput){super(message);this.exitCode=exitCode;this.auditOutput=auditOutput;}
 public int exitCode(){return exitCode;}
 public String auditOutput(){return auditOutput;}
}
