# demo-gh-tf-vault

This demo uses **Terraform** and **GitHub Actions** to automatically deploy two environments, staging and production, each with an EC2 instance with Vault installed.
Vault is configured to:
- Initialize and unseal automatically using an **AWS KMS key**.
- Store initialization information, including the **root token**, securely in **AWS Parameter Store**.

## Post-Deployment Instructions

Once the GitHub Actions workflow completes, you can connect to the EC2 instance using **EC2 Instance Connect** and follow the steps below to verify the setup:
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
- Verify Vault is initialized and unsealed:
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
- Login with the root token. Get the token from Parameter Store:
```
$ vault login
Token (will be hidden): 
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                  Value
---                  -----
token                <token>
token_accessor       <token_accessor>
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```
- Access the Vault UI with the root token: 
```
http://<vault_ec2_public_IP>:8200/ui/
```

# 1. Additional configs and tests

This section demonstrates two test scenarios configured with Vault.

### Test 1 - Using Vault AWS Auth
Vault can be configured to automatically generate AWS credentials for other AWS services like EC2s or Lambdas.
For this test, Terraform also deploys a dummy EC2 instance with a dummy IAM role that can authenticate to Vault.

In Vault: 
- Verify the AWS Auth method, and its config. In this example clients must send the `${environment}-vault.example.com` header, otherwise it won't work:
```
$ vault auth list
Path      Type     Accessor               Description                Version
----      ----     --------               -----------                -------
aws/      aws      auth_aws_d0f2146e      n/a                        n/a
token/    token    auth_token_012dfc42    token based credentials    n/a

$ vault read auth/aws/config/client
Key                           Value
---                           -----
access_key                    n/a
allowed_sts_header_values     <nil>
endpoint                      n/a
iam_endpoint                  n/a
iam_server_id_header_value    staging-vault.example.com
identity_token_audience       n/a
identity_token_ttl            0s
max_retries                   -1
role_arn                      n/a
sts_endpoint                  n/a
sts_region                    n/a
use_sts_region_from_client    false
```
- Verify the Vault Role which is bound it to the dummy IAM Role used by the dummy EC2, and is also linked to a Vault policy:
```
$ vault read auth/aws/role/test1
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
policies                          [test1-ec2 test2-ec2]
resolve_aws_unique_ids            false
role_id                           7816faf0-27e0-fe27-2453-69bfab203eac
role_tag                          n/a
token_bound_cidrs                 []
token_explicit_max_ttl            0s
token_max_ttl                     1h
token_no_default_policy           false
token_num_uses                    0
token_period                      0s
token_policies                    [test1-ec2 test2-ec2]
token_ttl                         15m
token_type                        default
```

- Verify kv-v2 secrets engine is enabled and the test secret was created:
```
$ vault secrets list
Path          Type         Accessor              Description
----          ----         --------              -----------
aws/          aws          aws_46ad58a7          n/a
cubbyhole/    cubbyhole    cubbyhole_45d37457    per-token private secret storage
identity/     identity     identity_4254d29c     identity store
kv-v2/        kv           kv_af356f23           n/a
sys/          system       system_3d9042e9       system endpoints used for control, policy and debugging

$ vault kv get kv-v2/test1/mysecret
====== Secret Path ======
kv-v2/data/test1/mysecret

======= Metadata =======
Key                Value
---                -----
created_time       2024-11-07T10:10:14.98417707Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

====== Data ======
Key         Value
---         -----
password    password123
username    admin
```
- Verify the policy was created to allow read and list the kv-v2 secret created above:
```
$ vault policy read test1-ec2
path "kv-v2/data/test1/mysecret" {
  capabilities = ["read", "list"]
}
```

In the dummy EC2:
- Test you can authenticate and get the secret:
```
$ vault login -method=aws role="test1" header_value="staging-vault.example.com"

$ vault kv get kv-v2/test1/mysecret
```

### Test 2 - Using Vault to generate dynamic AWS credentials for AWS
Vault can be configured to automatically generate AWS credentials related to another AWS Role in the same or in a different Account where Vault is deployed.
In this way, someone or something, can ask for AWS credentials to perform whatever is allowed by the other AWS Role that is being assumed.

In Vault:
- Verify AWS secrets engine was enabled:
```
$ vault secrets list
Path          Type         Accessor              Description
----          ----         --------              -----------
aws/          aws          aws_46ad58a7          n/a
cubbyhole/    cubbyhole    cubbyhole_45d37457    per-token private secret storage
identity/     identity     identity_4254d29c     identity store
kv-v2/        kv           kv_af356f23           n/a
sys/          system       system_3d9042e9       system endpoints used for control, policy and debugging
```
- Verify the Vault iam role with permissions to assume the other role
The dummy role `arn:aws:iam::632758144135:role/vault-s3-access-role` is created by Terraform and it allows S3 full access.
```
$ vault read aws/roles/s3_access
Key                         Value
---                         -----
credential_type             assumed_role
default_sts_ttl             0s
external_id                 n/a
iam_groups                  <nil>
iam_tags                    <nil>
max_sts_ttl                 0s
mfa_serial_number           n/a
permissions_boundary_arn    n/a
policy_arns                 <nil>
policy_document             n/a
role_arns                   [arn:aws:iam::632758144135:role/staging-vault-s3-access-role]
session_tags                <nil>
user_path                   n/a
```
In the dummy EC2:
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

## 2. References

- [Vault with AWS on Udemy](https://www.udemy.com/course/integrating-hashicorp-vault-with-aws)
- [HashiCorp Vault Examples on GitHub](https://github.com/btkrausen/hashicorp/)
- [Guide to Setting Up Vault on AWS EC2](https://patelsaheb.medium.com/setup-hashicorp-vault-on-aws-ec2-87d513b31b77)
- [Terraform AWS Vault Raft User Data Template](https://github.com/giuliocalzolari/terraform-aws-vault-raft/blob/main/templates/userdata.tpl#L179)
