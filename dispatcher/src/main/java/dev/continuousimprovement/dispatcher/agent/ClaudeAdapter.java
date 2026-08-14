package dev.continuousimprovement.dispatcher.agent;
import dev.continuousimprovement.dispatcher.ProcessRunner;import java.nio.file.*;import java.util.List;
public final class ClaudeAdapter extends AbstractCliAdapter {public ClaudeAdapter(ProcessRunner r,String e){super(r,e);}public String name(){return "claude";}protected List<String> arguments(String e,String p,Path result){return List.of(e,"-p",p,"--output-format","json","--max-turns","20","--allowedTools","Read,Edit,Write,Bash(./gradlew test:*)","--disallowedTools","WebFetch,WebSearch");}}
