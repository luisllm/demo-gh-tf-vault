# demo-gh-tf-vault
This demo uses Terraform and Github Actions to automatically deploy two environments, staging and production, with an EC2 instance with Vault installed in it.
Vault is automatically initialized and unseal using an AWS KMS key. The init info as well as the root token are stored in AWS Parameter Store.

Once the workflow finishes, connect to the EC2 via Instance Connect and:
- Verify Vault is running as a service:
```
$ sudo systemctl status vault
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
$ export VAULT_ADDR=http://127.0.0.1:8200
$ vault status
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

- Access the Vault UI: 
```
http://<vault_ec2_public_IP>:8200/ui/
```

# 1. Additional configs and tests

### Test 1 - Using Vault AWS Auth
Vault can be configured to automatically generate AWS credentials for other AWS services like EC2s or Lambdas.
To test this use case, the Terraform code also deploys a dummy EC2 with a dummy IAM Role attached to it. Vault is automatically configured to 
Vault Secrets AWS 
In Vault:
- Enable AWS Auth:
```
$ vault auth enable aws
```
- Configure AWS Auth. In this example clients must send the `${environment}-vault.example.com` header, otherwise it won't work:
```
$ vault write auth/aws/config/client \
  iam_server_id_header_value=staging-vault.example.com

$ vault read auth/aws/config/client
Key                           Value
---                           -----
access_key                    n/a
allowed_sts_header_values     <nil>
endpoint                      n/a
iam_endpoint                  n/a
iam_server_id_header_value    vault.example.com
identity_token_audience       n/a
identity_token_ttl            0s
max_retries                   -1
role_arn                      n/a
sts_endpoint                  n/a
sts_region                    n/a
use_sts_region_from_client    false
```
- Create a Role and bound it to the dummy IAM Role used by the dummy EC2. Also link the Role to a Vault policy:
```
$ vault write auth/aws/role/test \
  auth_type=iam \
  token_ttl=15m \
  max_ttl=1h \
  policies=test-ec2 \
  resolve_aws_unique_ids=false \
  bound_iam_principal_arn=arn:aws:iam::632758144135:role/staging-dummy-role
Success! Data written to: auth/aws/role/test

$ vault read auth/aws/role/test
Key                               Value
---                               -----
allow_instance_migration          false
auth_type                         iam
bound_account_id                  []
bound_ami_id                      []
bound_ec2_instance_id             <nil>
bound_iam_instance_profile_arn    []
bound_iam_principal_arn           [arn:aws:iam::632758144135:role/staging-dummy-role]
bound_iam_principal_id            []
bound_iam_role_arn                []
bound_region                      []
bound_subnet_id                   []
bound_vpc_id                      []
disallow_reauthentication         false
inferred_aws_region               n/a
inferred_entity_type              n/a
max_ttl                           1h
policies                          [test-ec2]
resolve_aws_unique_ids            false
role_id                           800a2b07-7fd9-aacc-f1da-f4151ee37713
role_tag                          n/a
token_bound_cidrs                 []
token_explicit_max_ttl            0s
token_max_ttl                     1h
token_no_default_policy           false
token_num_uses                    0
token_period                      0s
token_policies                    [test-ec2]
token_ttl                         15m
token_type                        default
```

- Enable kv-v2 secrets engine and create a test secret:
```
$ vault secrets enable kv-v2
Success! Enabled the kv-v2 secrets engine at: kv-v2/

$ vault kv put kv-v2/test/mysecret username=admin password=password123
====== Secret Path ======
kv-v2/data/test/mysecret

======= Metadata =======
Key                Value
---                -----
created_time       2024-11-06T20:12:07.224866085Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
```
- Create the policy to allow read and list the kv-v2 secret created above:
```
$ cat test-ec2-policy.hcl 
path "kv-v2/data/test/mysecret" {
  capabilities = ["read", "list"]
}

$ vault policy write test-ec2 test-ec2-policy.hcl 
Success! Uploaded policy: test-ec2
```

In the dummy EC2:
- Test you can authenticate and get the secret:
```
$ export VAULT_ADDR="http://<vault_server_private_ip>:8200"

$ vault login -method=aws role="test1" header_value="staging-vault.example.com"

$ vault kv get kv-v2/test1/mysecret
```

### Test 2 - Using Vault to generate dynamic AWS credentials for AWS
Vault can be configured to automatically generate AWS credentials related to another AWS Role in the same or in a different Account where Vault is deployed.
In this way, someone or something, can ask for AWS credentials to perform whatever is allowed by the other AWS Role that is being assumed.

In Vault:
- Enable AWS secrets engine:
```
$ vault secrets enable aws
```
- Create Vault iam role with permissions to assume the other role
The dummy role `arn:aws:iam::632758144135:role/vault-s3-access-role` is created by Terraform and it allows S3 read access.
```
$ vault write aws/roles/s3_access \
  role_arns=arn:aws:iam::632758144135:role/vault-s3-access-role \
  credential_type=assumed_role
```
- Ask for credentials:
```
$ vault write aws/sts/s3_access -ttl=60m
```
- The command above will give you some AWS credentials. For testing, export them to the following variables and test the s3 access:
```
$ export AWS_ACCESS_KEY_ID=""
$ export AWS_SECRET_ACCESS_KEY=""
$ export AWS_SESSION_TOKEN=""
$ aws s3 ls
```

# 1. References
https://prima.udemy.com/course/integrating-hashicorp-vault-with-aws
https://github.com/btkrausen/hashicorp/
https://patelsaheb.medium.com/setup-hashicorp-vault-on-aws-ec2-87d513b31b77
https://github.com/giuliocalzolari/terraform-aws-vault-raft/blob/main/templates/userdata.tpl#L179