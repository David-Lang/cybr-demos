# Jenkins Setup

Instructions on how to set up the demo environment  

#### Run the demo setup if not already done 
```
./setup.sh 
```

======== Configuration info ========= 

## Use RDP to login 
Go to the jenkins in a browser: http:\\FQDN:PORT
login with default password 
complete default plugin install
create admin user: admin
save and finnish

## Install Conjur Plugin
Manage Jenkins:Manage Plugins:Available Plugins 
search: Conjur Secrets
Check checkbox: "Restart Jenkins when installation is complete... "

## Configure Conjur Plugin
Manage Jenkins:Configure System

*Scroll Down to Conjur Appliance  
Enter Conjur details

*Scroll Down to Conjur JWT Authentication  
Enter Conjur JWT details
make sure checkboxes are checked: 
- Enable JWT Key Set endpoint 
- Enable Context Aware Credential Stores 

Save 

## Create a Jenkins Job
Manage Jenkins
Dashboard
Create a new Job (Pipeline) 
**name: new-identity**
copy "freestyle.sh" contents into Pipeline:Definition:Script  
Save
Dashboard:cybrlab-pipeline:Configuration:General
Refresh Credential Store
Dashboard:cybrlab-pipeline:Credentials
Inspect Credentials

Run the pipeline
look at the "Console Output" 
look at the file output artifact

## Jenkins Job Logging
Configure a new log recorder

Select Logger:
Type\Select: org.conjur.jenkins
Log Level: All

## On Jenkins server/container add Edge cert to Java cert store: cacerts
```

# update jenkins container with Conjur Cloud Cert

root@ossjenkins:/etc/ssl/certs/java# openssl s_client -showcerts -connect isp-poc.secretsmgr.cyberark.cloud:443 < /dev/null 2> /dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > isp-poc.pem
root@ossjenkins:/etc/ssl/certs/java# /usr/lib/jvm/java-11-openjdk-amd64/bin/keytool -import -alias cc -keystore cacerts -file isp-poc.pem

# default certstore password is: changeit

####

conjur_fqdn="tbd.secretsmgr.cyberark.cloud"

# show cert info
openssl s_client -showcerts -connect $conjur_fqdn:443 < /dev/null

# single cert
openssl s_client -showcerts -connect $conjur_fqdn:443 < /dev/null 2> /dev/null | openssl x509 -outform PEM > $conjur_fqdn.pem

# chain
openssl s_client -showcerts -connect $conjur_fqdn:443 < /dev/null 2> /dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >  $conjur_fqdn.pem 

# jenkins/jenkins:lts location for cacerts
ls -l /opt/java/openjdk/lib/security/cacerts
# other possible location forcacerts
#ls -l /etc/ssl/certs/java

cd /opt/java/openjdk/lib/security
keytool -import -alias $conjur_fqdn -keystore cacerts -file $conjur_fqdn.pem
```

Links:

https://plugins.jenkins.io/conjur-credentials/


Other Guides: https://www.conjur.org/blog/adding-conjur-secrets-management-to-your-jenkins-pipeline/
