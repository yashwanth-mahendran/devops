# Ansible Interview Preparation Guide

## Table of Contents
1. [Core Concepts](#core-concepts)
2. [Architecture](#architecture)
3. [Inventory Management](#inventory-management)
4. [Playbooks](#playbooks)
5. [Roles](#roles)
6. [Variables](#variables)
7. [Vault](#vault)
8. [Modules](#modules)
9. [Handlers](#handlers)
10. [Templates](#templates)
11. [Conditionals & Loops](#conditionals--loops)
12. [Error Handling](#error-handling)
13. [Best Practices](#best-practices)
14. [Interview Questions](#interview-questions)

---

## Core Concepts

### What is Ansible?
Ansible is an open-source **agentless** automation tool for:
- Configuration Management
- Application Deployment
- Task Automation
- IT Orchestration

### Key Features
| Feature | Description |
|---------|-------------|
| Agentless | No software needed on managed nodes (uses SSH/WinRM) |
| Idempotent | Running same playbook multiple times = same result |
| Declarative | Define desired state, Ansible handles how to get there |
| YAML-based | Human-readable configuration files |
| Push-based | Control node pushes configuration to managed nodes |

### Ansible vs Other Tools
| Feature | Ansible | Puppet | Chef | Terraform |
|---------|---------|--------|------|-----------|
| Language | YAML | Ruby DSL | Ruby | HCL |
| Architecture | Agentless | Agent-based | Agent-based | Agentless |
| Mode | Push | Pull | Pull | Push |
| Learning Curve | Low | High | High | Medium |
| Use Case | Config Mgmt | Config Mgmt | Config Mgmt | Infrastructure |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     CONTROL NODE                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Playbooks  │  │  Inventory  │  │  ansible.cfg        │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         │                │                     │             │
│         └────────────────┼─────────────────────┘             │
│                          │                                   │
│                    ┌─────▼─────┐                             │
│                    │  Ansible  │                             │
│                    │  Engine   │                             │
│                    └─────┬─────┘                             │
└──────────────────────────┼──────────────────────────────────┘
                           │ SSH/WinRM
         ┌─────────────────┼─────────────────┐
         ▼                 ▼                 ▼
   ┌──────────┐      ┌──────────┐      ┌──────────┐
   │ Managed  │      │ Managed  │      │ Managed  │
   │ Node 1   │      │ Node 2   │      │ Node 3   │
   └──────────┘      └──────────┘      └──────────┘
```

### Components
1. **Control Node**: Machine where Ansible is installed
2. **Managed Nodes**: Target machines being configured
3. **Inventory**: List of managed nodes
4. **Playbooks**: YAML files defining automation tasks
5. **Modules**: Units of code that Ansible executes
6. **Plugins**: Extend Ansible functionality
7. **Facts**: System information gathered from managed nodes

---

## Inventory Management

### Static Inventory
```ini
# inventory/hosts
[webservers]
web1.example.com
web2.example.com ansible_host=192.168.1.101

[dbservers]
db1.example.com ansible_user=dbadmin
db2.example.com

[production:children]
webservers
dbservers

[all:vars]
ansible_user=admin
ansible_ssh_private_key_file=~/.ssh/id_rsa
```

### Dynamic Inventory
- AWS: `amazon.aws.aws_ec2`
- Azure: `azure.azcollection.azure_rm`
- GCP: `google.cloud.gcp_compute`
- Kubernetes: `kubernetes.core.k8s`

### Inventory Variables
| Variable | Description |
|----------|-------------|
| `ansible_host` | IP/hostname to connect to |
| `ansible_port` | SSH port (default: 22) |
| `ansible_user` | SSH username |
| `ansible_password` | SSH password (use vault!) |
| `ansible_ssh_private_key_file` | SSH private key path |
| `ansible_become` | Enable privilege escalation |
| `ansible_become_method` | Method (sudo, su, pbrun, etc.) |
| `ansible_python_interpreter` | Python path on managed node |

---

## Playbooks

### Playbook Structure
```yaml
---
# playbook.yml
- name: Configure Web Servers          # Play name
  hosts: webservers                     # Target hosts
  become: yes                           # Privilege escalation
  gather_facts: yes                     # Collect system facts
  vars:                                 # Play-level variables
    http_port: 80
  
  pre_tasks:                            # Tasks before roles
    - name: Update apt cache
      apt:
        update_cache: yes
  
  roles:                                # Include roles
    - common
    - webserver
  
  tasks:                                # Main tasks
    - name: Ensure nginx is installed
      apt:
        name: nginx
        state: present
  
  post_tasks:                           # Tasks after main tasks
    - name: Send notification
      debug:
        msg: "Deployment complete"
  
  handlers:                             # Triggered by notify
    - name: Restart nginx
      service:
        name: nginx
        state: restarted
```

### Playbook Execution Order
1. `pre_tasks`
2. `roles`
3. `tasks`
4. `post_tasks`
5. `handlers` (in order of definition, not notification)

---

## Roles

### Role Structure
```
roles/
└── webserver/
    ├── defaults/          # Default variables (lowest priority)
    │   └── main.yml
    ├── vars/              # Role variables (higher priority)
    │   └── main.yml
    ├── tasks/             # Task definitions
    │   └── main.yml
    ├── handlers/          # Handlers
    │   └── main.yml
    ├── templates/         # Jinja2 templates
    │   └── nginx.conf.j2
    ├── files/             # Static files
    │   └── index.html
    ├── meta/              # Role metadata and dependencies
    │   └── main.yml
    └── README.md          # Documentation
```

### Creating Roles
```bash
ansible-galaxy init role_name
```

### Role Dependencies
```yaml
# roles/webserver/meta/main.yml
---
dependencies:
  - role: common
    vars:
      some_var: value
  - role: firewall
    when: enable_firewall | default(true)
```

### Using Roles in Playbooks
```yaml
# Method 1: Simple
- hosts: webservers
  roles:
    - common
    - webserver

# Method 2: With parameters
- hosts: webservers
  roles:
    - role: webserver
      vars:
        http_port: 8080
      tags: web

# Method 3: include_role (dynamic)
- hosts: webservers
  tasks:
    - include_role:
        name: webserver
      vars:
        http_port: 8080

# Method 4: import_role (static)
- hosts: webservers
  tasks:
    - import_role:
        name: webserver
```

---

## Variables

### Variable Precedence (Lowest to Highest)
1. Role defaults (`roles/x/defaults/main.yml`)
2. Inventory file or script group vars
3. Inventory `group_vars/all`
4. Playbook `group_vars/all`
5. Inventory `group_vars/*`
6. Playbook `group_vars/*`
7. Inventory file or script host vars
8. Inventory `host_vars/*`
9. Playbook `host_vars/*`
10. Host facts / cached `set_facts`
11. Play vars
12. Play `vars_prompt`
13. Play `vars_files`
14. Role vars (`roles/x/vars/main.yml`)
15. Block vars (only for tasks in block)
16. Task vars (only for the task)
17. `include_vars`
18. `set_facts` / registered vars
19. Role params
20. `include` params
21. Extra vars (`-e "var=value"`) - **HIGHEST PRIORITY**

### Variable Types
```yaml
# Simple variables
username: admin
port: 8080

# Lists
packages:
  - nginx
  - php
  - mysql

# Dictionaries
user:
  name: admin
  uid: 1000
  groups:
    - wheel
    - docker

# Accessing variables
"{{ username }}"
"{{ user.name }}"
"{{ user['name'] }}"
"{{ packages[0] }}"
```

### Special Variables
| Variable | Description |
|----------|-------------|
| `hostvars` | Access vars from other hosts |
| `groups` | All groups in inventory |
| `group_names` | Groups current host belongs to |
| `inventory_hostname` | Current host's inventory name |
| `ansible_facts` | Gathered facts |
| `play_hosts` | Active hosts in current play |

---

## Vault

### What is Ansible Vault?
Ansible Vault encrypts sensitive data like passwords, API keys, and certificates.

### Vault Commands
```bash
# Create encrypted file
ansible-vault create secrets.yml

# Edit encrypted file
ansible-vault edit secrets.yml

# Encrypt existing file
ansible-vault encrypt vars.yml

# Decrypt file
ansible-vault decrypt vars.yml

# View encrypted file
ansible-vault view secrets.yml

# Rekey (change password)
ansible-vault rekey secrets.yml

# Encrypt string
ansible-vault encrypt_string 'secret_password' --name 'db_password'
```

### Using Vault in Playbooks
```yaml
# Include vault file
- hosts: all
  vars_files:
    - vars/main.yml
    - vars/vault.yml  # Encrypted file
  tasks:
    - name: Use secret variable
      debug:
        msg: "Password is {{ vault_db_password }}"
```

### Running Playbooks with Vault
```bash
# Prompt for password
ansible-playbook playbook.yml --ask-vault-pass

# Use password file
ansible-playbook playbook.yml --vault-password-file ~/.vault_pass

# Multiple vault passwords (vault IDs)
ansible-playbook playbook.yml --vault-id dev@prompt --vault-id prod@~/.vault_pass_prod
```

### Vault Best Practices
1. Never commit vault passwords to version control
2. Use `vault_` prefix for encrypted variables
3. Use separate vault files for different environments
4. Use vault IDs for multiple environments
5. Store vault password securely (e.g., HashiCorp Vault, AWS Secrets Manager)

---

## Modules

### Common Modules

#### Package Management
```yaml
# apt (Debian/Ubuntu)
- apt:
    name: nginx
    state: present
    update_cache: yes

# yum (RHEL/CentOS)
- yum:
    name: httpd
    state: latest

# package (generic)
- package:
    name: vim
    state: present
```

#### File Operations
```yaml
# file module
- file:
    path: /etc/app/config
    state: directory
    mode: '0755'
    owner: app
    group: app

# copy module
- copy:
    src: files/config.yml
    dest: /etc/app/config.yml
    mode: '0644'

# template module
- template:
    src: templates/nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    validate: nginx -t -c %s
```

#### Service Management
```yaml
- service:
    name: nginx
    state: started
    enabled: yes

# systemd specific
- systemd:
    name: nginx
    state: restarted
    daemon_reload: yes
```

#### User Management
```yaml
- user:
    name: deploy
    groups: sudo,docker
    shell: /bin/bash
    create_home: yes
    generate_ssh_key: yes
```

#### Command Execution
```yaml
# command (no shell features)
- command: /usr/bin/uptime

# shell (supports pipes, redirects)
- shell: cat /etc/passwd | grep admin

# raw (no Python required)
- raw: yum install -y python3

# script (run local script remotely)
- script: scripts/setup.sh
```

---

## Handlers

### What are Handlers?
Handlers are tasks that run only when notified. They run at the end of all tasks in a play.

```yaml
tasks:
  - name: Update nginx config
    template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    notify:                          # Notify handler
      - Restart nginx
      - Reload firewall

handlers:
  - name: Restart nginx
    service:
      name: nginx
      state: restarted
    listen: "restart web services"   # Listen keyword
  
  - name: Reload firewall
    command: firewall-cmd --reload
```

### Handler Behavior
- Run only once even if notified multiple times
- Run in order defined, not order notified
- Run at end of play (use `meta: flush_handlers` to force earlier)

---

## Templates

### Jinja2 Template Basics
```jinja2
{# This is a comment #}

{# Variables #}
server_name {{ ansible_hostname }};

{# Conditionals #}
{% if nginx_ssl_enabled %}
listen 443 ssl;
{% else %}
listen 80;
{% endif %}

{# Loops #}
{% for server in upstream_servers %}
server {{ server.host }}:{{ server.port }};
{% endfor %}

{# Filters #}
{{ variable | default('default_value') }}
{{ list | join(',') }}
{{ string | upper }}
{{ password | password_hash('sha512') }}
```

### Common Filters
| Filter | Description |
|--------|-------------|
| `default(value)` | Set default if undefined |
| `mandatory` | Fail if undefined |
| `join(sep)` | Join list elements |
| `to_yaml` | Convert to YAML |
| `to_json` | Convert to JSON |
| `regex_replace` | Regex substitution |
| `hash('sha256')` | Hash string |
| `b64encode` | Base64 encode |

---

## Conditionals & Loops

### Conditionals
```yaml
# when clause
- name: Install Apache on RedHat
  yum:
    name: httpd
  when: ansible_os_family == "RedHat"

# Multiple conditions
- name: Install package
  apt:
    name: nginx
  when:
    - ansible_os_family == "Debian"
    - ansible_distribution_version is version('20.04', '>=')

# Boolean logic
when: (inventory_hostname in groups['webservers']) or (deploy_web | bool)
```

### Loops
```yaml
# Simple loop
- name: Create users
  user:
    name: "{{ item }}"
  loop:
    - alice
    - bob

# Loop with dict
- name: Create users with groups
  user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
  loop:
    - { name: alice, groups: admin }
    - { name: bob, groups: developer }

# Loop with index
- name: Loop with index
  debug:
    msg: "{{ index }} - {{ item }}"
  loop: "{{ items }}"
  loop_control:
    index_var: index
    label: "{{ item.name }}"  # Limit output
```

### Loop vs with_*
| New Syntax | Old Syntax |
|------------|------------|
| `loop` | `with_list` |
| `loop` + `flatten` | `with_flattened` |
| `loop` + `dict2items` | `with_dict` |
| `loop` + `fileglob` | `with_fileglob` |
| `loop` + `subelements` | `with_subelements` |

---

## Error Handling

### Ignore Errors
```yaml
- name: This might fail
  command: /bin/false
  ignore_errors: yes
```

### Failed When
```yaml
- name: Custom failure condition
  command: /usr/bin/check_status
  register: result
  failed_when: "'FAILED' in result.stdout"
```

### Changed When
```yaml
- name: Custom changed condition
  shell: /usr/bin/update_config
  register: result
  changed_when: result.rc == 2
```

### Block/Rescue/Always
```yaml
- name: Error handling block
  block:
    - name: Try this
      command: /bin/risky_command
    
    - name: If above succeeds, do this
      command: /bin/next_step
  
  rescue:
    - name: If block fails, do this
      command: /bin/recovery
  
  always:
    - name: Always do this
      debug:
        msg: "Block completed"
```

### Any Errors Fatal
```yaml
- hosts: all
  any_errors_fatal: true  # Stop all hosts on first error
  tasks:
    - name: Critical task
      command: /bin/critical
```

---

## Best Practices

### 1. Directory Structure
```
ansible-project/
├── ansible.cfg
├── inventory/
│   ├── production/
│   │   ├── hosts
│   │   ├── group_vars/
│   │   └── host_vars/
│   └── staging/
│       ├── hosts
│       ├── group_vars/
│       └── host_vars/
├── playbooks/
│   ├── site.yml
│   ├── webservers.yml
│   └── dbservers.yml
├── roles/
├── library/          # Custom modules
├── filter_plugins/   # Custom filters
└── README.md
```

### 2. Naming Conventions
- Use lowercase with underscores
- Prefix variables with role name: `nginx_port`
- Prefix vault variables: `vault_db_password`
- Use descriptive task names

### 3. Idempotency
- Always check if change is needed before making it
- Use `creates` and `removes` with command module
- Prefer specific modules over shell/command

```yaml
# Good - Idempotent
- apt:
    name: nginx
    state: present

# Bad - Not idempotent
- shell: apt-get install nginx
```

### 4. Security
- Never hardcode secrets
- Use vault for sensitive data
- Limit become privilege
- Use SSH keys, not passwords
- Keep ansible.cfg secure

### 5. Performance
- Use `async` for long-running tasks
- Limit gathering facts when not needed
- Use `serial` for rolling updates
- Use `strategy: free` when ordering doesn't matter

### 6. Testing
```bash
# Syntax check
ansible-playbook --syntax-check playbook.yml

# Dry run
ansible-playbook --check playbook.yml

# Diff mode
ansible-playbook --diff playbook.yml

# Use molecule for role testing
molecule test
```

---

## Interview Questions

### Basic Questions

**Q1: What is Ansible and what makes it different from other configuration management tools?**
> Ansible is an agentless, open-source automation tool that uses SSH to manage nodes. Unlike Puppet or Chef, it doesn't require agents on managed nodes, uses simple YAML syntax, and operates on a push-based model.

**Q2: What is idempotency in Ansible?**
> Idempotency means running the same playbook multiple times produces the same result. Ansible modules check current state before making changes, so if the desired state already exists, no changes are made.

**Q3: Explain the difference between playbook, play, and task.**
> - **Playbook**: YAML file containing one or more plays
> - **Play**: Mapping of hosts to tasks/roles
> - **Task**: Single unit of action using a module

**Q4: What is the difference between `copy` and `template` modules?**
> - `copy`: Copies files as-is to remote hosts
> - `template`: Processes Jinja2 templates before copying

**Q5: How do you handle secrets in Ansible?**
> Using Ansible Vault to encrypt sensitive data. Create encrypted files with `ansible-vault create`, and run playbooks with `--ask-vault-pass` or `--vault-password-file`.

### Intermediate Questions

**Q6: Explain variable precedence in Ansible.**
> Variables have 22 levels of precedence. Key ones from lowest to highest:
> 1. Role defaults
> 2. Inventory variables
> 3. group_vars/host_vars
> 4. Play vars
> 5. Role vars
> 6. Task vars
> 7. Extra vars (-e) - highest

**Q7: What is the difference between `include_role` and `import_role`?**
> - `import_role`: Static - processed at playbook parsing time
> - `include_role`: Dynamic - processed during runtime, supports loops and conditionals

**Q8: How do handlers work?**
> Handlers are tasks triggered by `notify`. They run at the end of all tasks in a play, only once even if notified multiple times, in the order they're defined.

**Q9: How do you implement rolling updates?**
```yaml
- hosts: webservers
  serial: 2           # Update 2 hosts at a time
  max_fail_percentage: 25
  tasks:
    - name: Deploy application
      ...
```

**Q10: Explain block, rescue, and always.**
> - `block`: Group of tasks
> - `rescue`: Tasks to run if block fails
> - `always`: Tasks that always run regardless of success/failure

### Advanced Questions

**Q11: How do you create a custom module?**
> Create a Python script in `library/` directory. Use `AnsibleModule` class to handle arguments and return results. Modules should be idempotent and return changed status.

**Q12: Explain lookup plugins with examples.**
```yaml
# File lookup
password: "{{ lookup('file', '/etc/secrets/password') }}"

# Environment variable
home_dir: "{{ lookup('env', 'HOME') }}"

# AWS SSM Parameter
api_key: "{{ lookup('aws_ssm', 'api-key') }}"
```

**Q13: How do you implement zero-downtime deployments?**
> Using serial directive, health checks, and handlers:
> 1. Remove server from load balancer
> 2. Deploy new version
> 3. Run health checks
> 4. Add server back to load balancer

**Q14: How do you handle different environments?**
> - Separate inventory files/directories per environment
> - Use group_vars structure: `group_vars/production/`, `group_vars/staging/`
> - Use vault IDs for environment-specific secrets
> - Use `--limit` to target specific environments

**Q15: Explain Ansible Tower/AWX and its benefits.**
> Tower/AWX provides:
> - Web UI for Ansible
> - Role-based access control
> - Job scheduling
> - Credential management
> - Audit trails
> - REST API

---

## Quick Reference Commands

```bash
# Inventory
ansible-inventory --list                    # List all hosts
ansible-inventory --graph                   # Show inventory structure

# Ad-hoc commands
ansible all -m ping                         # Test connectivity
ansible webservers -m shell -a "uptime"     # Run command
ansible all -m setup                        # Gather facts
ansible all -m setup -a "filter=ansible_*memory*"  # Filter facts

# Playbooks
ansible-playbook site.yml                   # Run playbook
ansible-playbook site.yml -l webservers     # Limit hosts
ansible-playbook site.yml --tags "config"   # Run specific tags
ansible-playbook site.yml --skip-tags "slow"  # Skip tags
ansible-playbook site.yml --start-at-task "Install nginx"  # Resume

# Debugging
ansible-playbook site.yml -v               # Verbose
ansible-playbook site.yml -vvvv            # Debug level
ansible-playbook site.yml --step           # Confirm each task

# Galaxy
ansible-galaxy install geerlingguy.docker  # Install role
ansible-galaxy collection install amazon.aws  # Install collection
ansible-galaxy init my_role                # Create role structure
```

---

## Next Steps
1. Start with beginner playbooks
2. Practice with local VMs or containers
3. Build roles for common tasks
4. Implement in CI/CD pipeline
5. Learn Ansible Tower/AWX
6. Contribute to Ansible Galaxy
