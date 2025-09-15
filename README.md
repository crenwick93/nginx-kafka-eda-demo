# nginx-kafka-eda-demo

Quickstart:

1) Copy example config files and edit:

```bash
cp inventory.example inventory
cp ansible.cfg.example ansible.cfg
cp playbooks/vars/prometheus-am.yml.example playbooks/vars/prometheus-am.yml
```

2) Put secrets in vault and run with vault password:

```bash
# Create/edit vault file (already exists): vault.yml
ansible-vault edit vault.yml

# Example vars you might store:
# vault_servicenow_password: "..."
# vault_eda_event_stream_token: "..."
```

3) Run playbooks:

```bash
ansible-playbook -i inventory playbooks/node-exporter-setup.yml
ansible-playbook -i inventory playbooks/prometheus-am-setup.yml --ask-vault-pass
```

Notes:
- `playbooks/vars/prometheus-am.yml` controls forwarder mode (webhook|kafka|servicenow) and endpoints.
- `playbooks/nginx-app-setup.yml` was removed because an `nginx` role is not included; add a role if needed.
- Sensitive local files like `vault.yml`, `inventory`, `ansible.cfg`, and concrete vars are gitignored; examples are provided.