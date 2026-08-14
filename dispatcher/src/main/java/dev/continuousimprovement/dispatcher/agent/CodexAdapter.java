package dev.continuousimprovement.dispatcher.agent;
import dev.continuousimprovement.dispatcher.ProcessRunner;import java.nio.file.Path;import java.util.List;
public final class CodexAdapter extends AbstractCliAdapter { public CodexAdapter(ProcessRunner r,String e){super(r,e);}public String name(){return "codex";}protected List<String> arguments(String e,String p,Path result){return List.of(e,"exec","--sandbox","workspace-write","--json","--output-last-message",result.toString(),p);} }
