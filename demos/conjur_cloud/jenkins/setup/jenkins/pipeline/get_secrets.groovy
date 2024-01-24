node {
   stage('get_secrets') {
    withCredentials([
     conjurSecretCredential(credentialsId: 'data-vault-poc-jenkins-account-ssh-user-1-username', variable: 'SSH_UNAME'),
     conjurSecretCredential(credentialsId: 'data-vault-poc-jenkins-account-ssh-user-1-password', variable: 'SSH_PWD')
    ]) {
      sh "echo -n SSH_UNAME:"
      sh "echo $SSH_UNAME | sed 's/./& /g'"
      sh "echo -n SSH_PWD:"
      sh "echo $SSH_PWD | sed 's/./& /g'"
      sh "echo SSH_UNAME=$SSH_UNAME >> demo.txt"
      sh "echo SSH_PWD=$SSH_PWD >> demo.txt"
    }
  }
}
`