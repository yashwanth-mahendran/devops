# Ansible Best Practices Guide

## Table of Contents
1. [Directory Structure](#directory-structure)
2. [Naming Conventions](#naming-conventions)
3. [Inventory Management](#inventory-management)
4. [Variable Management](#variable-management)
5. [Playbook Design](#playbook-design)
6. [Role Development](#role-development)
7. [Security](#security)
8. [Performance](#performance)
9. [Testing](#testing)
10. [CI/CD Integration](#cicd-integration)

---

## Directory Structure

### Recommended Project Layout

```
ansible-project/
├── ansible.cfg                 # Project configuration
├── requirements.yml            # Galaxy dependencies
├── site.yml                    # Master playbook
├── playbooks/                  # Specific playbooks
│   ├── webservers.yml
│   ├── dbservers.yml
│   └── deploy.yml
├── inventory/
│   ├── production/
│   │   ├── hosts               # Production inventory
│   │   ├── group_vars/
│   │   │   ├── all.yml
│   │   │   └── webservers.yml
│   │   └── host_vars/
│   │       └── server1.yml
│   ├── staging/
│   │   ├── hosts
│   │   ├── group_vars/
│   │   └── host_vars/
│   └── development/
│       └── ...
├── group_vars/                 # Global group vars
│   └── all/
│       ├── vars.yml
│       └── vault.yml           # Encrypted secrets
├── host_vars/                  # Global host vars
├── roles/
│   ├── common/
│   ├── webserver/
│   └── database/
├── library/                    # Custom modules
├── filter_plugins/             # Custom filters
├── callback_plugins/           # Custom callbacks
├── files/                      # Static files
├── templates/                  # Jinja2 templates
└── docs/                       # Documentation
```

### Key Principles
- **Separation of concerns**: Split by environment
- **Scalability**: Easy to add new environments
- **Maintainability**: Clear organization
- **Security**: Vault files separate from plain vars

---

## Naming Conventions

### Variables
```yaml
# Good - prefixed, descriptive, lowercase with underscores
nginx_http_port: 80
postgresql_max_connections: 200
app_deploy_user: deploy

# Bad
Port: 80
max_conn: 200
deployUser: deploy
```

### Vault Variables
```yaml
# Always prefix vault variables
vault_db_password: "encrypted"
vault_api_secret_key: "encrypted"
vault_ssl_private_key: "encrypted"
```

### Role Variables
```yaml
# Prefix with role name to avoid conflicts
nginx_worker_processes: auto
nginx_log_format: main
postgresql_version: 15
```

### Tasks
```yaml
# Good - descriptive, start with verb
- name: Install nginx package
- name: Configure nginx virtual hosts
- name: Ensure nginx service is running

# Bad
- name: nginx
- name: Config
- name: Do the thing
```

### Files and Directories
```
# Good
roles/webserver/templates/nginx.conf.j2
roles/webserver/files/ssl-cert.pem

# Bad
roles/WebServer/templates/NGINX.CONF.j2
```

---

## Inventory Management

### Static Inventory Best Practices
```ini
# Use descriptive group names
[webservers]
web1.prod.example.com
web2.prod.example.com

# Use children for logical grouping
[production:children]
webservers
dbservers

# Set vars at appropriate levels
[webservers:vars]
http_port=80

[production:vars]
environment=production
```

### Dynamic Inventory
- Use for cloud environments (AWS, Azure, GCP)
- Cache results for performance
- Use `keyed_groups` for automatic grouping

### Inventory Variables Priority
1. Command line (`-e`)
2. `host_vars` files
3. `group_vars` files
4. Inventory file variables

---

## Variable Management

### Variable Precedence (Know These!)
Highest to lowest priority:
1. Extra vars (`-e "var=value"`)
2. Task vars
3. Block vars
4. Role vars
5. Play vars
6. `host_vars/*`
7. `group_vars/*`
8. Role defaults

### Best Practices
```yaml
# Use defaults for overridable values
# roles/nginx/defaults/main.yml
nginx_port: 80

# Use vars for internal role values
# roles/nginx/vars/main.yml
_nginx_config_path: /etc/nginx

# Use group_vars for environment-specific
# group_vars/production.yml
nginx_worker_connections: 4096
```

### Avoid Magic Numbers
```yaml
# Bad
- pause:
    seconds: 300

# Good
- pause:
    seconds: "{{ health_check_timeout }}"
```

---

## Playbook Design

### Idempotency
```yaml
# Good - Idempotent
- name: Install nginx
  apt:
    name: nginx
    state: present

# Bad - Not idempotent
- name: Install nginx
  command: apt-get install nginx
```

### Use Handlers for Service Restarts
```yaml
tasks:
  - name: Update nginx config
    template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    notify: Restart nginx

handlers:
  - name: Restart nginx
    service:
      name: nginx
      state: restarted
```

### Use Tags
```yaml
- name: Install packages
  apt:
    name: nginx
  tags:
    - install
    - nginx

# Run specific tags
# ansible-playbook site.yml --tags "install"
```

### Error Handling
```yaml
- name: Deploy application
  block:
    - name: Download artifact
      get_url:
        url: "{{ artifact_url }}"
        dest: /tmp/app.tar.gz
    
    - name: Extract artifact
      unarchive:
        src: /tmp/app.tar.gz
        dest: /opt/app
  rescue:
    - name: Rollback on failure
      copy:
        src: /opt/app.backup/
        dest: /opt/app/
  always:
    - name: Cleanup temp files
      file:
        path: /tmp/app.tar.gz
        state: absent
```

---

## Role Development

### Role Structure Checklist
- [ ] `defaults/main.yml` - Default variables
- [ ] `vars/main.yml` - Internal variables
- [ ] `tasks/main.yml` - Main task list
- [ ] `handlers/main.yml` - Handlers
- [ ] `templates/` - Jinja2 templates
- [ ] `files/` - Static files
- [ ] `meta/main.yml` - Dependencies
- [ ] `README.md` - Documentation

### Role Dependencies
```yaml
# meta/main.yml
dependencies:
  - role: common
  - role: firewall
    vars:
      firewall_allowed_ports: [80, 443]
```

### Make Roles Reusable
```yaml
# Support multiple OS families
- name: Include OS-specific vars
  include_vars: "{{ ansible_os_family | lower }}.yml"

# Provide sensible defaults
# defaults/main.yml
nginx_port: 80
nginx_user: www-data
```

---

## Security

### Vault Usage
```bash
# Create encrypted file
ansible-vault create secrets.yml

# Encrypt existing file
ansible-vault encrypt plaintext.yml

# Use password file (not in repo!)
echo "mypassword" > ~/.vault_pass
chmod 600 ~/.vault_pass
ansible-playbook site.yml --vault-password-file ~/.vault_pass
```

### Sensitive Variables
```yaml
- name: Configure database
  mysql_user:
    name: "{{ db_user }}"
    password: "{{ vault_db_password }}"
  no_log: true  # Hide output
```

### SSH Security
```yaml
# ansible.cfg
[defaults]
host_key_checking = True

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=yes
```

### Limit Privilege Escalation
```yaml
# Only become when needed
- name: Install package
  apt:
    name: nginx
  become: yes

- name: Generate report
  command: date
  # No become needed
```

---

## Performance

### ansible.cfg Optimizations
```ini
[defaults]
forks = 50
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 86400

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
```

### Reduce Fact Gathering
```yaml
# Disable completely
- hosts: webservers
  gather_facts: no

# Gather specific subsets
- hosts: webservers
  gather_facts: yes
  gather_subset:
    - network
    - hardware
```

### Async for Long Tasks
```yaml
- name: Long running task
  command: /usr/local/bin/long_operation.sh
  async: 3600
  poll: 0
  register: async_result

- name: Check status
  async_status:
    jid: "{{ async_result.ansible_job_id }}"
  register: job_result
  until: job_result.finished
  retries: 60
  delay: 60
```

### Serial and Throttle
```yaml
# Rolling updates
- hosts: webservers
  serial: 2
  tasks:
    - name: Deploy
      ...

# Limit concurrent tasks
- name: API call with rate limiting
  uri:
    url: https://api.example.com/action
  throttle: 5
```

---

## Testing

### Syntax Check
```bash
ansible-playbook --syntax-check site.yml
```

### Dry Run (Check Mode)
```bash
ansible-playbook --check site.yml
```

### Diff Mode
```bash
ansible-playbook --check --diff site.yml
```

### Molecule Testing
```bash
# Install molecule
pip install molecule molecule-docker

# Initialize role with molecule
molecule init role my_role

# Run tests
cd my_role
molecule test
```

### Ansible-lint
```bash
# Install
pip install ansible-lint

# Run
ansible-lint playbook.yml

# With custom rules
ansible-lint -c .ansible-lint playbook.yml
```

---

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Ansible CI

on: [push, pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install ansible ansible-lint yamllint
      
      - name: Lint playbooks
        run: ansible-lint .
      
      - name: Syntax check
        run: ansible-playbook --syntax-check site.yml

  molecule:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: pip install molecule molecule-docker ansible
      
      - name: Run Molecule tests
        run: molecule test
        working-directory: roles/webserver
```

### Pre-commit Hooks
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/ansible/ansible-lint
    rev: v6.22.0
    hooks:
      - id: ansible-lint
        files: \.(yaml|yml)$
```

---

## Quick Reference

### Common Commands
```bash
# Run playbook
ansible-playbook site.yml

# Limit to hosts/groups
ansible-playbook site.yml -l webservers

# Extra variables
ansible-playbook site.yml -e "env=production version=1.0"

# Step through tasks
ansible-playbook site.yml --step

# Start at specific task
ansible-playbook site.yml --start-at-task "Deploy app"

# List tasks
ansible-playbook site.yml --list-tasks

# List hosts
ansible-playbook site.yml --list-hosts
```

### Debugging
```bash
# Verbose output
ansible-playbook site.yml -v    # Level 1
ansible-playbook site.yml -vvv  # Level 3
ansible-playbook site.yml -vvvv # Level 4 (connection debugging)

# Debug module
- debug:
    var: my_variable
    
- debug:
    msg: "Value is {{ my_variable }}"
```
