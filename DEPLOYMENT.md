# Deploying Frappe Lending on Coolify

This guide walks you through deploying Frappe Lending on Coolify.

## Prerequisites

- Coolify instance (self-hosted or cloud)
- Git repository access (GitHub, GitLab, etc.)
- Domain name (optional but recommended)
- Minimum server specs:
  - 2 vCPU
  - 4 GB RAM
  - 20 GB storage

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                      Coolify                            │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │  Frappe Lending  │  │  PostgreSQL  │  │   Redis   │ │
│  │    (Main App)    │  │  (Database)  │  │  (Cache)  │ │
│  │                  │  │              │  │           │ │
│  │  - Web Server    │  │  External or │  │  Queue    │ │
│  │  - Scheduler     │◄─┤  Coolify-    │  │  SocketIO │ │
│  │  - Workers       │  │  managed     │  │           │ │
│  │  - SocketIO      │  │              │  │           │ │
│  └────────┬─────────┘  └──────────────┘  └───────────┘ │
│           │                                             │
│           ▼                                             │
│  ┌─────────────────────────────────────────────────────┤
│  │               Traefik (Reverse Proxy)               │
│  │            SSL/TLS + Domain Routing                 │
│  └─────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────┘
```

---

## Deployment Options

### Option A: Full Stack (Recommended for Isolation)

Deploy PostgreSQL, Redis, and the app together.

### Option B: External Database

Use Coolify-managed PostgreSQL or external database service.

---

## Step-by-Step Deployment

### Step 1: Push Code to Git Repository

1. Ensure all Docker files are committed:
   ```bash
   git add Dockerfile docker-compose.yml docker-compose.external-db.yml .env.example docker/
   git commit -m "feat: add Docker configuration for Coolify deployment"
   git push origin main
   ```

### Step 2: Create a New Project in Coolify

1. Log into your Coolify dashboard
2. Click **"New Project"**
3. Name it: `Frappe Lending` or similar

### Step 3: Add Resources

#### Option A: Deploy Full Stack with Docker Compose

1. In your project, click **"Add Resource"**
2. Select **"Docker Compose"**
3. Connect your Git repository
4. Set the **Compose file path**: `docker-compose.yml`
5. Configure environment variables (see Step 4)
6. Click **Deploy**

#### Option B: Deploy with External Database

1. **First, create a PostgreSQL database in Coolify:**
   - Add Resource → Database → PostgreSQL
   - Note the connection string

2. **Then deploy the application:**
   - Add Resource → Docker Compose
   - Use `docker-compose.external-db.yml`
   - Set `DATABASE_URL` to the PostgreSQL connection string

### Step 4: Configure Environment Variables

In Coolify, add these environment variables:

| Variable | Required | Example Value | Description |
|----------|----------|---------------|-------------|
| `SITE_NAME` | Yes | `lending.example.com` | Your site name |
| `ADMIN_PASSWORD` | Yes | `SecurePassword123!` | Admin login password |
| `DOMAIN` | Yes | `lending.example.com` | Your domain |
| `DATABASE_URL` | If external DB | `postgres://user:pass@host:port/db` | PostgreSQL connection |
| `DB_PASSWORD` | If local DB | `frappe_password` | Database password |
| `ENABLE_SOCKETIO` | No | `true` | Real-time updates |
| `DEVELOPER_MODE` | No | `0` | Keep 0 for production |

### Step 5: Configure Domain & SSL

1. In Coolify, go to your service settings
2. Under **"Domains"**, add your domain
3. Enable **"Auto SSL"** for automatic Let's Encrypt certificates
4. Coolify will configure Traefik automatically

### Step 6: Deploy and Initialize

1. Click **"Deploy"** in Coolify
2. Watch the build logs for any errors
3. First deployment will:
   - Build the Docker image (may take 10-15 minutes)
   - Initialize the Frappe bench
   - Create the site
   - Install ERPNext and Lending apps
   - Run database migrations

### Step 7: Access Your Application

1. Once deployed, access: `https://lending.yourdomain.com`
2. Login with:
   - **Username**: `Administrator`
   - **Password**: Your `ADMIN_PASSWORD`

---

## Post-Deployment Setup

### 1. Create Your First User

```
Settings → User → New User
```

### 2. Configure Company

```
Setup Wizard → Company Details
```

### 3. Set Up Lending Configuration

```
Lending Settings → Configure loan products, charges, etc.
```

### 4. Configure Scheduled Jobs

The scheduler runs automatically with these daily tasks:
- Interest accrual
- Loan demand processing
- Security shortfall monitoring
- Loan classification (NPA)
- Line of Credit auto-closure

---

## Troubleshooting

### Build Failures

1. **Out of memory during build:**
   - Increase server RAM to at least 4GB
   - Or build locally and push the image

2. **Network timeout:**
   - Check Coolify server's internet connectivity
   - Verify GitHub/GitLab is accessible

### Application Not Starting

1. **Check logs in Coolify:**
   ```
   Service → Logs
   ```

2. **Database connection issues:**
   - Verify DATABASE_URL is correct
   - Check PostgreSQL is running
   - Ensure network connectivity between services

3. **Redis connection issues:**
   - Verify Redis service is healthy
   - Check Redis logs

### Site Not Accessible

1. **DNS not propagated:**
   - Wait for DNS propagation (up to 48 hours)
   - Use `dig yourdomain.com` to verify

2. **SSL certificate issues:**
   - Check Traefik logs
   - Ensure domain points to Coolify server IP

---

## Maintenance Commands

### Access Container Shell

In Coolify terminal or SSH:
```bash
docker exec -it frappe-lending /entrypoint.sh shell
```

### Run Bench Commands

```bash
docker exec -it frappe-lending /home/frappe/.local/bin/bench --site lending.localhost [command]
```

### Backup Site

```bash
docker exec -it frappe-lending /home/frappe/.local/bin/bench --site lending.localhost backup
```

### Run Migrations

```bash
docker exec -it frappe-lending /home/frappe/.local/bin/bench --site lending.localhost migrate
```

### Clear Cache

```bash
docker exec -it frappe-lending /home/frappe/.local/bin/bench --site lending.localhost clear-cache
```

---

## Scaling Considerations

### For Higher Load

1. **Increase workers:**
   Edit `docker/supervisord.conf` and increase `numprocs` for workers

2. **Separate services:**
   Run scheduler and workers as separate containers

3. **Database scaling:**
   Use managed PostgreSQL (AWS RDS, DigitalOcean, etc.)

4. **Redis clustering:**
   Use managed Redis for high availability

---

## File Structure

```
lending/
├── Dockerfile                    # Main Docker build file
├── docker-compose.yml            # Full stack deployment
├── docker-compose.external-db.yml # External database deployment
├── .env.example                  # Environment template
├── docker/
│   ├── entrypoint.sh            # Container entrypoint script
│   └── supervisord.conf         # Process manager config
└── DEPLOYMENT.md                # This file
```

---

## Support

- **Frappe Forum**: https://discuss.frappe.io
- **ERPNext Documentation**: https://docs.erpnext.com
- **Coolify Documentation**: https://coolify.io/docs

---

## Security Checklist

- [ ] Change default `ADMIN_PASSWORD`
- [ ] Enable SSL/TLS (auto with Coolify)
- [ ] Set `DEVELOPER_MODE=0` in production
- [ ] Configure firewall to only expose ports 80/443
- [ ] Set up regular backups
- [ ] Keep Docker images updated
