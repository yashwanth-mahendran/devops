# Common Role

Ansible role for common server configuration including security hardening, user management, and system configuration.

## Requirements

- Ansible 2.9 or higher
- Supported OS: Ubuntu 20.04+, Debian 11+, RHEL/CentOS 8+

## Role Variables

### User Management

| Variable | Default | Description |
|----------|---------|-------------|
| `common_users` | `[]` | List of users to create |
| `common_users_removed` | `[]` | List of users to remove |
| `common_admin_group` | `admins` | Admin group name |

Example user:
```yaml
common_users:
  - name: deploy
    groups: [admins, docker]
    shell: /bin/bash
    ssh_key: "ssh-rsa AAAA..."
    sudo: true
    nopasswd: true
```

### SSH Security

| Variable | Default | Description |
|----------|---------|-------------|
| `common_disable_root_login` | `true` | Disable SSH root login |
| `common_disable_password_auth` | `true` | Disable password authentication |
| `common_ssh_allowed_users` | `[]` | Allowed SSH users |

### Firewall & Security

| Variable | Default | Description |
|----------|---------|-------------|
| `common_install_fail2ban` | `true` | Install fail2ban |
| `common_configure_firewall` | `true` | Configure UFW |
| `common_firewall_allowed_ports` | `["22"]` | Allowed ports |

### Packages

| Variable | Default | Description |
|----------|---------|-------------|
| `common_packages` | See defaults | Packages to install |
| `common_upgrade_packages` | `false` | Upgrade all packages |

### System

| Variable | Default | Description |
|----------|---------|-------------|
| `common_timezone` | `UTC` | System timezone |
| `common_set_hostname` | `true` | Set hostname |
| `common_configure_limits` | `true` | Configure system limits |

## Dependencies

None

## Example Playbook

```yaml
- hosts: all
  become: yes
  roles:
    - role: common
      vars:
        common_timezone: America/New_York
        common_users:
          - name: deploy
            groups: [sudo, docker]
            ssh_key: "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
            sudo: true
```

## Tags

- `security` - Security hardening tasks
- `users` - User management tasks
- `packages` - Package installation
- `system` - System configuration
- `upgrade` - Package upgrades

## License

MIT

## Author

Your Name
