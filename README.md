# SAS Cloud Rapid Deployment common templates

These templates assume a topology with an "ansible controller" VM and one or more SAS/Viya VMs.

The "ansible controller" serves as jump host into the environment, and may be the only machine with a public IP address.

The intent of these templates is to simplify the creation of software install templates for any cloud platform, 
any topology and for any product combination.

This project is meant to be included as a "git submodule" into your git project, in a directory names "common":

```
 myproject
   - common (-> quickstart-sas-viya-common)
     - playbooks
       - ...
     - scripts
       - ...
   - playbooks
   - scripts
   - templates
   ...
```

If you want to modify/overwrite any of of the scripts or playbooks roles in "common", copy them to the corresponding "scripts" or "playbooks" directory in your project. 




### Overview: How to create your own Cloud Rapid Deployment template

- create the infrastructure (networks, VMs, firewalls) using the cloud provider's templating language (e.g. AWS Cloudformation on AWS, Azure Resource Manager, terraform ... )
- include this project as git submodule into your git project
- modify the files with the static definitions to match your topology
  - `playbooks/group_vars/`
  - `playbooks/inventory.ini`
- implement any parts of the scripts and playbooks that have cloud-specific elements and/or need to be added or modified
- run the provided prereq shell scripts on the the VMs
- run the deployment playbooks on the ansible controller

### How the playbooks and roles and scripts work

Most of the steps for the deployment are being implemented in ansible. You find all that code in the `playbooks` directory. 
The bootstrapping code at the very beginning (which, among other things, installs ansible) uses `bash`. You find that code in the `scripts` directory.    

When you create your infrastructure, all the cloud provider's templating languages provide some way to execute bootstrapping code on the VMs (usually some form of [cloud-init](https://cloud-init.io/), often implemented as `UserData` VM attribute).
That is where you kick off scripts that download the scripts and ansible playbooks to your VMs and then execute those scripts and playbooks.

First, you execute the bootstrapping scripts on each VM, which set up the necessary pieces so that the VMs can communicate with each other.
After that, everything will be driven by a number of playbooks executed from the ansible controller.

You invoke a series of ansible playbooks, which in turn execute a number of roles. Using playbooks and roles allows us to clearly structure the process. 
Each logical step corresponds to a role, and the roles are grouped into separate playbook invocations which correspond to the main deployment steps (environment preparation, install, post-install steps etc.) 

You can change the implementation of each role, or add additional roles.

To change the implementation of a role, copy it into the corresponding location in the `playbooks` directory in your project and modify it there.
The overwritten role will automatically be picked up (controller by an ansible search path option).

During the preparation steps, the project files will be copied to the following file structure on the ansible controller; 

```
/sas/install
|-- common
|   |-- playbooks
|   `-- scripts
|-- playbooks
`-- scripts
...
```


TODO: explain lookthrough (roles_path = /sas/install/playbooks/roles;/sas/install/common/playbooks/roles). Problem: the roles in the in the current playbook directory are being used first, no matter the roles_path.
If we invoke the playbooks in /common, it'll never find overrides with the same name elsewhere.  

Controlling everything through ansible playbook roles allows us to 
- specify the topology in only one place: the `inventory.ini` file
- define all global variables in only one place: the `group_vars` files. 
- make any changes or overrides to individual steps by modifying the existing roles
- adding steps as needed by simply adding additional roles   





### Install users

All scripts and templates are written to be executed by an "install user" with sudo privileges.
It needs to be the same user on all VMs.

 AWS      | Azure  | Google 
:-------- |:-------|:-------
 `ec2-user` | `vmuser` |        



### Step 0.0 - Input parameter validation

TODO

### Step 0.1 VM post initialization -executed on the individual hosts


1. __Ansible controller VM setup (optional)__
   - yum installs
   - security config
   - ...

   Should be called inline in VM bootstrap ("user-data" section or equivalent)

1. __Ansible controller VM prereqs__
    - install java, ansible, git
    - export nfs share
    - create ansible ssh key
    ```
    scripts/ansiblecontroller_prereqs.sh
     --->/tmp/prereqs.sh &> /tmp/prereqs.log
    ```

1. __SAS VMs setup (optional)__
 
   - yum installs
   - security config
   - ...

   Should be called inline in VM bootstrap ("user-data" section or equivalent)
 
1. __SAS VMs prereqs__
    - mount nfs share
    - set ansible ssh key
    - post readiness flag
   ```
    scripts/sasnodes_prereqs.sh
     --->/tmp/prereqs.sh &> /tmp/prereqs.log
    ```

1. __Ansible controller download project files__
    download all the additional scripts and playbooks need for the deployment. 
    This part must be implemented per cloud (e.g. AWS used the aws cli do download the project files from s3, while Azure used the azure cli, etc.)
    ```
    scripts/download_file_tree.sh
     --->/tmp/download_file_tree.sh &> /tmp/download_file_tree.log
    ```
    
### Step 1 Additional preparatory steps - driven by ansible from the ansible controller  

The playbook `playbooks\prepare_nodes.yml` does additional steps needed before installing SAS, including
- host routing
- volume attachments
- setting up directories and users 

Logs are routed to `/var/log/sas/install/prepare_nodes.yml`
 
Example invocation:
``` 
  export ANSIBLE_LOG_PATH=/var/log/sas/install/prepare_nodes.log
  export ANSIBLE_CONFIG=/sas/install/common/playbooks/ansible.cfg
  ansible-playbook -v /sas/install/common/playbooks/prepare_nodes.yml \
                   -e "USERLIB_DISK=/dev/xvdl" \
                   -e "SAS_INSTALL_DISK=/dev/xvdg" \
                   -e "CASCACHE_DISK="
```

NB: All roles executed via the ````prepare_nodes.yml```` playbook are tagged with their name. 
E.g. if you want to run ````prepare_nodes.yml```` and exclude ````set_host_routing````, invoke it with
````
ansible-playbook prepare_nodes.yml --skip-tags set_host_routing
````

1. __Wait for all SAS VMs to be ready__

    Waits for all hosts to post their readiness flag in the ````/sas/install/nfs/readiness_flags```` directory.

    ```    
    Role: prepare_nodes/wait_for_viya_vms
    ```

1. __Set up hosts routing__

    Add routing information into the ````/etc/hosts```` file on all machines and set hostnames.
    This is not needed if other host routing mechanisms are in place (e.g. Azure provides a built-in dns server that allows to set hostnames for the VMs).
    
    (Reminder: to skip this role, add ````--skip-tags set_host_routing``` to the playbook invocation)

    ```
    Role: prepare_nodes/set_host_routing
    ```

1. __Create SASWORK dir__

    Creates the ````/sastmp/saswork```` directory on all machines in the ````[ProgrammingServicesServers]```` host group.  
    
    ```
    Inputs: 
       group_vars: 
         SASWORK_DIR: "/sastmp/saswork"     
    Role: prepare_nodes/create_saswork_dir
    ```
    
1. __Mount disks__

    Mounts disks on the SAS VMs for the SAS Installation directory and user library
    
    ```
    Host Groups:
       NeedMountUserlibDrive
       NeedMountSASInstallDrive
    Inputs: 
       group_vars: 
         SAS_INSTALL_DIR: "/opt/sas"
         USERLIB_DIR: "/opt/sas/viya/config/data/cas"       
       extra_vars: SAS_INSTALL_DISK, USERLIB_DISK
    Role: prepare_nodes/create_saswork_dir
    ```
    
1. __Mount disks for CAS Cache__

    Mounts disks on the SAS VMs for the SAS Installation directory and user library
    
    ```
    Host Groups:
       CASControllerServer
    Inputs: 
       group_vars: 
         CASCACHE_DIR: "/sastmp/cascache"
       extra_vars: CASCACHE_DISK
    Role: prepare_nodes/mount_disk
          If no disk is passed in it assumes ephemeral disks or no mount and executes
          prepare_nodes/mount_cascache
    ```
    
    
### Step 2 Set up Users  (OpenLDAP install)

The playbook `playbooks\openldapsetup.yml` sets up an OpenLDAP server that can be used as initial identity provider for SAS Viya.
Out of the box, these two groups and users are being created:
```
   Group: sasadmin
    User: sasadmin
    
   Group: sasusers
    User: sasuser
```
You can edit the `user_list` variable in `group_vars\openldapall.yml` to create additional users in the `sasusers` group.

```    
    Host Groups:
       OpenLdapServer: single machine that runs the OpenLDAP server
       OpenLdapClients: all machines to configure with the openldap server  
    Inputs: 
       - group_vars/openldapall.yml
       - OLCROOTPW: base64 encoded password for adminuser
       - OLCUSERPW: base64 encoded password for sasuser  
     
```

Example invocation (from aws cfn-init):
``` 
  command: !Sub
    - |
      if [ -n "${ADMINPASS}" ]  && [ -n "${USERPASS}" ]; then
        su -l ec2-user -c '
          export ANSIBLE_LOG_PATH=/var/log/sas/install/openldap.log
          export ANSIBLE_CONFIG=/sas/install/common/playbooks/ansible.cfg
          ansible-playbook -v /sas/install/common/playbooks/openldapsetup.yml \
            -e "OLCROOTPW='${ADMINPASS}'" \
            -e "OLCUSERPW='${USERPASS}'"
        '
      fi
    - USERPASS: !Base64
        "Ref": SASUserPass
      ADMINPASS: !Base64
        "Ref": SASAdminPass
```    

### Step 3 Prepare Deployment files

The playbook `playbooks\prepare_deployment.yml` does additional steps needed before installing SAS, including
- download sas-orchestration
- build playbook from SOE file
- modify inventory.ini and vars.yml


Logs are routed to `/var/log/sas/install/prepare_deployment.yml`
 
Example invocation:
``` 
  export ANSIBLE_LOG_PATH=/var/log/sas/install/prepare_deployment.log
  export ANSIBLE_CONFIG=/sas/install/common/playbooks/ansible.cfg
  ansible-playbook -v /sas/install/common/playbooks/prepare_deployment.yml 
```
