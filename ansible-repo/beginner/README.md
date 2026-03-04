# Beginner Ansible Examples

Start your Ansible journey with these basic examples. Each playbook introduces fundamental Ansible concepts.

## Prerequisites

```bash
# Install Ansible
pip install ansible

# For local testing, set up inventory
echo "localhost ansible_connection=local" > inventory/local
```

## Playbooks

### 01-hello-world.yml
Your first Ansible playbook. Prints messages and shows basic syntax.
- **Concepts**: plays, tasks, debug module
```bash
ansible-playbook beginner/01-hello-world.yml
```

### 02-package-install.yml
Install packages on different OS families (Debian/RedHat).
- **Concepts**: apt, yum, package modules, conditional installation
```bash
ansible-playbook beginner/02-package-install.yml -i inventory/hosts
```

### 03-file-management.yml
Create, copy, and manage files and directories.
- **Concepts**: file, copy, template modules, permissions
```bash
ansible-playbook beginner/03-file-management.yml
```

### 04-service-management.yml
Start, stop, and manage system services.
- **Concepts**: service, systemd modules, state management
```bash
ansible-playbook beginner/04-service-management.yml
```

### 05-variables.yml
Use variables and gather system facts.
- **Concepts**: vars, vars_files, facts, set_fact
```bash
ansible-playbook beginner/05-variables.yml
```

### 06-conditionals.yml
Conditional execution with when statements.
- **Concepts**: when, boolean operators, facts conditions
```bash
ansible-playbook beginner/06-conditionals.yml
```

### 07-loops.yml
Different types of loops in Ansible.
- **Concepts**: loop, with_items, loop_control, nested loops
```bash
ansible-playbook beginner/07-loops.yml
```

### 08-facts-gathering.yml
Gather and use system facts.
- **Concepts**: setup module, ansible_facts, custom facts, gather_subset
```bash
ansible-playbook beginner/08-facts-gathering.yml
```

### 09-error-handling.yml
Handle errors gracefully.
- **Concepts**: block/rescue/always, ignore_errors, failed_when, changed_when
```bash
ansible-playbook beginner/09-error-handling.yml
```

### 10-tags.yml
Selectively run tasks with tags.
- **Concepts**: tags, --tags, --skip-tags, always, never
```bash
# Run specific tags
ansible-playbook beginner/10-tags.yml --tags "install"

# Skip specific tags
ansible-playbook beginner/10-tags.yml --skip-tags "slow"

# List available tags
ansible-playbook beginner/10-tags.yml --list-tags
```

### 11-register-debug.yml
Register and debug task output.
- **Concepts**: register, debug, assert, verbosity
```bash
ansible-playbook beginner/11-register-debug.yml

```bash
ansible-playbook beginner/07-loops.yml
```

## Key Concepts

- **Playbooks**: YAML files containing plays
- **Plays**: Map hosts to tasks
- **Tasks**: Call Ansible modules
- **Modules**: Units of work (apt, yum, copy, etc.)
- **Inventory**: List of managed hosts
- **Facts**: System information gathered automatically

## Tips

1. Always use `--check` for dry runs
2. Use `-vvv` for verbose output
3. Test on localhost first
4. Read error messages carefully
5. Check syntax with `--syntax-check`
