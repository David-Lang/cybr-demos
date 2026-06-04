// Creates root pipeline job for GlobalCredentials identity (init.groovy.d).
import jenkins.model.Jenkins
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition

def jobName = 'global-credentials-demo'
def scriptFile = new File(Jenkins.instance.rootDir, 'get_secrets.groovy')

if (!scriptFile.exists()) {
  println("SKIP pipeline job: missing ${scriptFile}")
  return
}

def pipelineScript = scriptFile.text
def jenkins = Jenkins.instance
def job = jenkins.getItem(jobName)

if (job == null) {
  job = jenkins.createProject(WorkflowJob.class, jobName)
  println("Created pipeline job: ${jobName}")
} else {
  println("Updating pipeline job: ${jobName}")
}

job.definition = new CpsFlowDefinition(pipelineScript, true)
job.description = 'CyberArk Secrets Manager JWT demo (conjurSecretCredential)'
job.save()
