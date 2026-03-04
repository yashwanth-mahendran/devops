# Ansible Learning Repository

Comprehensive Ansible learning repository covering all concepts from beginner to advanced, designed for **interview preparation** and **best practices implementation**.

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [ANSIBLE_INTERVIEW_GUIDE.md](ANSIBLE_INTERVIEW_GUIDE.md) | Complete interview Q&A with concepts |
| [BEST_PRACTICES.md](BEST_PRACTICES.md) | Production-ready best practices |

## 📁 Repository Structure

```
ansible-repo/
├── ansible.cfg                 # Ansible configuration
├── site.yml                    # Master playbook
├── requirements.yml            # Galaxy dependencies
├── beginner/                   # Basic concepts (11 playbooks)
│   ├── 01-hello-world.yml
│   ├── 02-package-install.yml
│   ├── 03-file-management.yml
│   ├── 04-service-management.yml
│   ├── 05-variables.yml
│   ├── 06-conditionals.yml
│   ├── 07-loops.yml
│   ├── 08-facts-gathering.yml
│   ├── 09-error-handling.yml
│   ├── 10-tags.yml
│   └── 11-register-debug.yml
├── intermediate/               # Intermediate patterns (8+ playbooks)
│   ├── 01-handlers.yml
│   ├── 02-templates.yml
│   ├── 03-include-import.yml
│   ├── 04-vault.yml
│   ├── 05-async.yml
│   ├── 06-delegation.yml
│   ├── 07-lookups.yml
│   ├── 08-filters.yml
│   ├── tasks/                  # Reusable task files
│   └── templates/              # Jinja2 templates
├── advanced/                   # Advanced patterns (7 playbooks)
│   ├── 01-docker-deploy.yml
│   ├── 02-k8s-deploy.yml
│   ├── 03-rolling-deployment.yml
│   ├── 04-dynamic-inventory.yml
│   ├── 05-custom-modules.yml
│   ├── 06-molecule-testing.yml
│   └── 07-performance-optimization.yml
├── roles/                      # Complete role examples
│   ├── common/                 # System hardening role
│   │   ├── defaults/
│   │   ├── tasks/
│   │   ├── handlers/
│   │   ├── templates/
│   │   ├── vars/
│   │   └── meta/
│   └── webserver/              # Nginx webserver role
│       ├── defaults/
│       ├── tasks/
│       ├── handlers/
│       ├── templates/
│       └── meta/
├── inventory/                  # Inventory examples
│   ├── hosts                   # Static inventory
│   └── aws_ec2.yml             # Dynamic inventory (AWS)
├── group_vars/                 # Group variables
│   ├── all.yml
│   ├── webservers.yml
│   ├── dbservers.yml
│   ├── production.yml
│   └── dev.yml
├── host_vars/                  # Host-specific variables
│   ├── prod-web1.yml
│   └── prod-db-primary.yml
├── vault/                      # Vault examples
│   ├── README.md
│   ├── vault_example.yml
│   └── vault_playbook.yml
└── playbooks/                  # Production playbooks
    ├── common.yml
    ├── webservers.yml
    ├── dbservers.yml
    ├── loadbalancers.yml
    └── monitoring.yml
```

## 🚀 Quick Start

### Installation
```bash
# Install Ansible
pip install ansible ansible-lint

# Install Galaxy requirements
ansible-galaxy install -r requirements.yml
```

### Basic Commands
```bash
# Test connectivity
ansible all -m ping -i inventory/hosts

# Run beginner playbook (dry run)
ansible-playbook beginner/01-hello-world.yml --check

# Run with verbosity
ansible-playbook beginner/01-hello-world.yml -v

# Run master playbook
ansible-playbook -i inventory/production/hosts site.yml
```

## 📖 Learning Path

### 🟢 Beginner (Start Here)
| # | Playbook | Concepts Covered |
|---|----------|------------------|
| 1 | `01-hello-world.yml` | First playbook, debug module |
| 2 | `02-package-install.yml` | apt/yum modules, package management |
| 3 | `03-file-management.yml` | file, copy, template modules |
| 4 | `04-service-management.yml` | service, systemd modules |
| 5 | `05-variables.yml` | vars, vars_files, set_fact |
| 6 | `06-conditionals.yml` | when clause, boolean logic |
| 7 | `07-loops.yml` | loop, with_items, loop_control |
| 8 | `08-facts-gathering.yml` | setup module, ansible_facts |
| 9 | `09-error-handling.yml` | block/rescue/always, ignore_errors |
| 10 | `10-tags.yml` | tags, skip-tags, always/never |
| 11 | `11-register-debug.yml` | register, debug, assertions |

### 🟡 Intermediate
| # | Playbook | Concepts Covered |
|---|----------|------------------|
| 1 | `01-handlers.yml` | handlers, notify, listen |
| 2 | `02-templates.yml` | Jinja2 templates, filters |
| 3 | `03-include-import.yml` | include_tasks, import_tasks, include_role |
| 4 | `04-vault.yml` | ansible-vault, encrypted vars |
| 5 | `05-async.yml` | async, poll, async_status |
| 6 | `06-delegation.yml` | delegate_to, local_action, run_once |
| 7 | `07-lookups.yml` | lookup plugins, file, env, pipe |
| 8 | `08-filters.yml` | Jinja2 filters, data manipulation |

### 🔴 Advanced
| # | Playbook | Concepts Covered |
|---|----------|------------------|
| 1 | `01-docker-deploy.yml` | Docker containers with Ansible |
| 2 | `02-k8s-deploy.yml` | Kubernetes deployments |
| 3 | `03-rolling-deployment.yml` | Zero-downtime deployments, serial |
| 4 | `04-dynamic-inventory.yml` | AWS EC2 dynamic inventory |
| 5 | `05-custom-modules.yml` | Writing custom modules/plugins |
| 6 | `06-molecule-testing.yml` | Role testing with Molecule |
| 7 | `07-performance-optimization.yml` | Forks, pipelining, caching |

## 🎯 Interview Topics Covered

### Core Concepts
- ✅ Ansible Architecture (Control Node, Managed Nodes)
- ✅ Agentless vs Agent-based
- ✅ Idempotency
- ✅ Push vs Pull model

### Inventory
- ✅ Static inventory
- ✅ Dynamic inventory (AWS, Azure)
- ✅ Inventory variables
- ✅ Groups and children

### Variables
- ✅ Variable precedence (22 levels!)
- ✅ group_vars / host_vars
- ✅ Facts and custom facts
- ✅ Magic variables

### Playbooks
- ✅ Plays, tasks, modules
- ✅ Handlers and notify
- ✅ Conditionals and loops
- ✅ Error handling
- ✅ Tags

### Roles
- ✅ Role structure
- ✅ defaults vs vars
- ✅ Dependencies
- ✅ Galaxy roles

### Security
- ✅ Ansible Vault
- ✅ Vault IDs
- ✅ encrypt_string
- ✅ No-log

### Advanced
- ✅ Lookups and filters
- ✅ Custom modules
- ✅ Delegation
- ✅ Async tasks
- ✅ Rolling updates

## 🛠 Best Practices Implemented

1. **Directory Structure**: Environment-based organization
2. **Naming Conventions**: Lowercase, underscores, prefixes
3. **Idempotency**: All playbooks are idempotent
4. **Security**: Vault for all secrets
5. **Roles**: Reusable, documented roles
6. **Testing**: Molecule-ready roles
7. **Documentation**: README for every role

## 📝 Quick Reference Commands

```bash
# Inventory
ansible-inventory --list                     # List all hosts
ansible-inventory --graph                    # Show inventory structure

# Ad-hoc
ansible all -m ping                          # Test connectivity
ansible webservers -m shell -a "uptime"      # Run command
ansible all -m setup -a "filter=*memory*"    # Get facts

# Playbook
ansible-playbook site.yml                    # Run playbook
ansible-playbook site.yml -l webservers      # Limit hosts
ansible-playbook site.yml --tags "install"   # Run tags
ansible-playbook site.yml --check --diff     # Dry run with diff

# Vault
ansible-vault create secrets.yml             # Create encrypted file
ansible-vault edit secrets.yml               # Edit encrypted file
ansible-vault encrypt_string 'secret'        # Encrypt string

# Galaxy
ansible-galaxy install -r requirements.yml  # Install dependencies
ansible-galaxy init my_role                  # Create role skeleton
```

## 📚 Resources

- [Official Documentation](https://docs.ansible.com/)
- [Ansible Galaxy](https://galaxy.ansible.com/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/index.html)
- [Ansible Examples](https://github.com/ansible/ansible-examples)

## 📄 License

MIT License - Feel free to use for learning and production!
