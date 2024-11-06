# demo-gh-tf-vault
This demo uses Terraform and Github Actions to automatically deploy two environments, staging and production, with an EC2 instance with Vault installed in it.
Vault is automatically initialized and unseal using an AWS KMS key. The init info as well as the root token are stored in AWS Parameter Store.

Once the workflow finishes, connect to the EC2 via Instance Connect and:
- Verify vault is running as a service:
```
ubuntu@ip-10-0-1-217:~$ sudo systemctl status vault
● vault.service - HashiCorp Vault
     Loaded: loaded (/etc/systemd/system/vault.service; enabled; vendor preset: enabled)
     Active: active (running) since Wed 2024-11-06 15:22:02 UTC; 2min 57s ago
       Docs: https://www.vaultproject.io/docs/
   Main PID: 388 (vault)
      Tasks: 8 (limit: 1078)
     Memory: 228.7M
        CPU: 1.626s
     CGroup: /system.slice/vault.service
             └─388 /usr/bin/vault server -config=/etc/vault.d/vault-config.hcl

Nov 06 15:22:05 ip-10-0-1-217 vault[388]: 2024-11-06T15:22:05.432Z [INFO]  rollback: Starting the rollback manager with 256 workers
Nov 06 15:22:05 ip-10-0-1-217 vault[388]: 2024-11-06T15:22:05.433Z [INFO]  rollback: starting rollback manager
Nov 06 15:22:05 ip-10-0-1-217 vault[388]: 2024-11-06T15:22:05.434Z [INFO]  core: restoring leases
Nov 06 15:22:05 ip-10-0-1-217 vault[388]: 2024-11-06T15:22:05.439Z [INFO]  expiration: lease restore complete
Nov 06 15:22:05 ip-10-0-1-217 vault[388]: 2024-11-06T15:22:05.461Z [INFO]  identity: entities restored
Nov 06 15:22:05 ip-10-0-1-217 vault[388]: 2024-11-06T15:22:05.461Z [INFO]  identity: groups restored
Nov 06 15:22:05 ip-10-0-1-217 vault[388]: 2024-11-06T15:22:05.469Z [INFO]  core: starting raft active node
Nov 06 15:22:05 ip-10-0-1-217 vault[388]: 2024-11-06T15:22:05.485Z [INFO]  storage.raft: starting autopilot: config="CleanupDeadServers:false LastContactThreshold:10s DeadServerLastContactThreshold:24h0m0s MaxTrailingLogs:1000 MinQuorum>
Nov 06 15:22:05 ip-10-0-1-217 vault[388]: 2024-11-06T15:22:05.485Z [INFO]  core: usage gauge collection is disabled
Nov 06 15:22:05 ip-10-0-1-217 vault[388]: 2024-11-06T15:22:05.563Z [INFO]  core: post-unseal setup complete
```
- Verify Vault is initialized 
```
ubuntu@ip-10-0-1-217:~$ export VAULT_ADDR=http://127.0.0.1:8200
ubuntu@ip-10-0-1-217:~$ vault status
Key                      Value
---                      -----
Seal Type                awskms
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    5
Threshold                3
Version                  1.18.1
Build Date               2024-10-29T14:21:31Z
Storage Type             raft
Cluster Name             vault-cluster-30c266e2
Cluster ID               6a53d74c-734b-e476-d0a9-fd45caab55e3
HA Enabled               true
HA Cluster               https://127.0.0.1:8201
HA Mode                  active
Active Since             2024-11-06T15:22:05.563977358Z
Raft Committed Index     282
Raft Applied Index       282
```

- Access the Vault UI: http://<vault_ec2_public_IP>:8200/ui/
