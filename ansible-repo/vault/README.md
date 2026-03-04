# Vault Examples Directory

This directory contains examples of using Ansible Vault for secrets management.

## Quick Commands

```bash
# Create new encrypted file
ansible-vault create secrets.yml

# Edit encrypted file
ansible-vault edit secrets.yml

# Encrypt existing file
ansible-vault encrypt plaintext.yml

# Decrypt file
ansible-vault decrypt encrypted.yml

# View encrypted content
ansible-vault view secrets.yml

# Change vault password
ansible-vault rekey secrets.yml

# Encrypt single string
ansible-vault encrypt_string 'my_secret_value' --name 'my_variable'
```

## Running Playbooks with Vault

```bash
# Prompt for password
ansible-playbook playbook.yml --ask-vault-pass

# Use password file
ansible-playbook playbook.yml --vault-password-file ~/.vault_pass

# Multiple vault IDs
ansible-playbook playbook.yml \
  --vault-id dev@~/.vault_pass_dev \
  --vault-id prod@~/.vault_pass_prod
```

## Files in this Directory

- `vault_example.yml` - Example vault file structure (NOT encrypted - for reference)
- `vault_playbook.yml` - Playbook demonstrating vault usage
- `.vault_pass_example` - Example vault password file format

## Best Practices

1. **Never commit vault passwords** to version control
2. Use `.gitignore` to exclude vault password files
3. Prefix vault variables with `vault_` for clarity
4. Use separate vault files per environment
5. Consider using external secret managers (HashiCorp Vault, AWS Secrets Manager)
