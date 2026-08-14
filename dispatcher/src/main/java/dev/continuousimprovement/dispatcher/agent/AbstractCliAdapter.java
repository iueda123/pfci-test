package dev.continuousimprovement.dispatcher.agent;
import dev.continuousimprovement.core.JsonSupport;import dev.continuousimprovement.core.model.AgentResult;import dev.continuousimprovement.dispatcher.ProcessRunner;
import java.nio.file.*;import java.time.Duration;import java.util.*;
abstract class AbstractCliAdapter implements AgentAdapter {
 /** Inlined result contract: agents cannot be relied on to open schemas/agent-result.schema.json themselves. */
 static final String CONTRACT="""
Write ONLY this JSON object to %s, with no markdown fence and no commentary:
{"outcome":"changed|needs_info|no_change|failed","summary":"what you did, max 4000 characters","tests":[{"command":"./gradlew test","result":"passed|failed|not_run"}],"filesChanged":["relative/path"],"risks":["..."],"questions":["..."]}
All six keys are required. tests, filesChanged, risks and questions are always JSON arrays: write [] when empty and a one-element array for a single entry, never a bare object or string.
""";
 private final ProcessRunner runner;private final String executable;AbstractCliAdapter(ProcessRunner r,String e){runner=r;executable=e;}
 protected abstract List<String> arguments(String executable,String prompt,Path result);
 public AgentExecution execute(Path worktree,Path evidence,String prompt,Path resultFile,Duration timeout)throws Exception{
  String bounded=prompt+"\nRead-only redacted evidence: "+evidence+"\n"+evidenceFiles(evidence)+CONTRACT.formatted(resultFile)+"Do not push, merge, deploy, or access credentials.";
  var run=runner.run(arguments(executable,bounded,resultFile),worktree,timeout,Map.of());AgentResult result=null;
  if(Files.isRegularFile(resultFile)){result=read(run,()->JsonSupport.AGENT_RESULT_MAPPER.readValue(resultFile.toFile(),AgentResult.class));}else if(run.succeeded()){result=read(run,()->{var json=JsonSupport.AGENT_RESULT_MAPPER.readTree(run.output());return json.has("result")&&json.path("result").isTextual()?JsonSupport.AGENT_RESULT_MAPPER.readValue(json.path("result").asText(),AgentResult.class):JsonSupport.AGENT_RESULT_MAPPER.treeToValue(json,AgentResult.class);});}if(result!=null)validate(run,result);
  if(run.succeeded()&&result==null)throw new AgentResultFormatException("agent did not produce result JSON",run.exitCode(),run.output());return new AgentExecution(run.exitCode(),run.timedOut(),run.output(),result);
 }
 /** Agents are not allowed to run directory listings, so the evidence file names have to be named in the prompt. */
 private static String evidenceFiles(Path evidence){List<String> names=List.of();try(var entries=Files.list(evidence)){names=entries.filter(Files::isRegularFile).map(p->p.getFileName().toString()).sorted().toList();}catch(Exception ignored){}
  return names.isEmpty()?"That directory holds no evidence files for this run.\n":"Evidence files: "+String.join(", ",names)+". Open each one with your file read tool; shell commands that list directories are denied.\n";}
 private interface Parser { AgentResult parse() throws Exception; }
 private AgentResult read(ProcessRunner.Result run,Parser parser)throws AgentResultFormatException{try{return parser.parse();}catch(Exception e){throw new AgentResultFormatException("agent result JSON does not match the required schema: "+e.getMessage(),run.exitCode(),run.output());}}
 private void validate(ProcessRunner.Result run,AgentResult r)throws AgentResultFormatException{if(r.summary()==null||r.summary().length()>4000||r.outcome()==null||r.tests()==null||r.filesChanged()==null||r.risks()==null||r.questions()==null)throw new AgentResultFormatException("invalid agent result",run.exitCode(),run.output());}
}
