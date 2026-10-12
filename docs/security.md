# Security Documentation

## Security and Operational Considerations

The project applies the following security controls:

- Restricted access controls
- Secure secret management
- Limited exposure to public networking
- SSH access protection
- Deployment validation and operational scripts

## Implemented Security Controls

| Control | Implementation |
|---|---|
| Network access control | Azure NSG restricts inbound access to approved CIDR ranges |
| SSH access | Port 22 is limited to approved CIDR ranges |
| SSH authentication | Password authentication is disabled and SSH public-key authentication is used |
| Web access | Web traffic is restricted by the NSG |
| Application isolation | Open WebUI runs inside Docker on internal port 8080 |
| Secret management | `WEBUI_SECRET_KEY` and `OPENAI_API_KEY` are provided through a local `.env` file |
| Git secret protection | `.env` is excluded from Git |
| Persistent storage | Open WebUI data is stored in the `open-webui-data` Docker volume |
| Validation | `validate.sh` checks Docker, Compose, container status, storage, port 80, and application health |
| Restart | `restart.sh` restarts Open WebUI and runs validation |
| Cleanup | `cleanup.sh` stops the stack while preserving persistent data by default |
| Cost control | Terraform supports automatic VM shutdown |

## Network Security Design

Current traffic flow:

```text
Client ==> Azure NSG ==> Public IP ==> Port 80 ==> Open WebUI container ==> Port 8080
```

The NSG allows:

- SSH on port 22 from approved CIDR ranges
- Web traffic on ports 80 and 443 from approved CIDR ranges

Open WebUI uses port 8080 internally and is exposed through host port 80.

## SSH Security

The VM disables password authentication and uses SSH public-key authentication.

```hcl
disable_password_authentication = true
```

SSH access is configured using:

```hcl
admin_ssh_key {
  username   = var.admin_username
  public_key = file(pathexpand(var.ssh_public_key_path))
}
```

## Secret Management

Sensitive values are provided through a local `.env` file.

The main variables are:

```text
WEBUI_SECRET_KEY
OPENAI_API_KEY
```

The `.env` file is excluded from Git and must not be committed.

The following must not be committed to the repository:

- `.env`
- API keys
- Passwords
- SSH private keys
- Terraform state files
- Azure credentials

## Operational Validation

The project includes three operational scripts.

### validate.sh

Checks:

- Docker availability
- Docker Compose availability
- Docker Compose configuration
- Open WebUI container status
- Persistent storage
- Port 80
- Open WebUI health endpoint
- `.env` availability

### restart.sh

Restarts Open WebUI and automatically runs `validate.sh` after the application becomes available.

### cleanup.sh

Stops the Docker stack while preserving persistent application data by default.

## Persistent Storage

Open WebUI stores application data in:

```text
open-webui-data
```

Local testing confirmed that the administrator account remained available after cleanup and redeployment.