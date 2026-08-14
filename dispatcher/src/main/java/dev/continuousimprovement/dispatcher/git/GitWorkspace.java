package dev.continuousimprovement.dispatcher.git;
import dev.continuousimprovement.dispatcher.ProcessRunner;import java.io.IOException;import java.nio.file.*;import java.time.Duration;import java.util.*;
public final class GitWorkspace implements AutoCloseable {
 private final ProcessRunner runner;private final Path repository,worktree;private final String branch;
 private GitWorkspace(ProcessRunner r,Path repo,Path work,String branch){runner=r;repository=repo;worktree=work;this.branch=branch;}
 public static GitWorkspace create(ProcessRunner runner,Path repository,Path parent,String branch)throws Exception{
  if(!branch.matches("agent/(codex|claude)/issue-[0-9]+-[a-f0-9]{4,12}"))throw new IllegalArgumentException("unsafe branch");Files.createDirectories(parent);Path work=parent.resolve(branch.replace('/','-')).normalize();if(!work.startsWith(parent.normalize()))throw new IllegalArgumentException("unsafe worktree");
  runRequired(runner,List.of("git","fetch","--prune","origin"),repository);runRequired(runner,List.of("git","remote","set-head","origin","--auto"),repository);runRequired(runner,List.of("git","worktree","add","-b",branch,work.toString(),"origin/HEAD"),repository);return new GitWorkspace(runner,repository,work,branch);
 }
 public Path path(){return worktree;}public String branch(){return branch;}
 public void commit(String message)throws Exception{runRequired(runner,List.of("git","add","--all"),worktree);runRequired(runner,List.of("git","-c","user.name=Improvement Dispatcher","-c","user.email=dispatcher@example.invalid","commit","-m",message),worktree);}
 public void push()throws Exception{runRequired(runner,List.of("git","push","--set-upstream","origin",branch),worktree);}
 public void close(){try{runner.runControl(List.of("git","worktree","remove","--force",worktree.toString()),repository,Duration.ofSeconds(30),Map.of());runner.runControl(List.of("git","worktree","prune"),repository,Duration.ofSeconds(10),Map.of());}catch(Exception ignored){}}
 static String runRequired(ProcessRunner r,List<String> c,Path d)throws Exception{var x=r.runControl(c,d,Duration.ofMinutes(2),Map.of());if(!x.succeeded())throw new IOException(String.join(" ",c)+" failed: "+x.output());return x.output();}
}
