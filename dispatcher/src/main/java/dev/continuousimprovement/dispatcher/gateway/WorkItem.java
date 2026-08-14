package dev.continuousimprovement.dispatcher.gateway;
import java.util.UUID;public record WorkItem(UUID reportId,long issueNumber,String issueTitle,String issueBody,String agent) {}
