# GitHub Copilot Metrics Collector

**Collect GitHub Copilot usage metrics for your organization or enterprise in 10 minutes.**

✨ **Updated February 2026** - Using latest GitHub Copilot Metrics API

---

## 🚀 Quick Setup

Choose your setup based on your GitHub structure:
- **Organization Setup** - Single GitHub organization
- **Enterprise Setup** - Multiple organizations under an enterprise

---

## 📋 Organization Setup

### 1. Install jq (30 seconds)

```bash
brew install jq  # macOS
# OR
sudo apt-get install -y jq  # Linux
```

### 2. Create GitHub App (5 minutes)

1. Go to: `https://github.com/organizations/YOUR_ORG/settings/apps`
2. Click **"New GitHub App"**
3. Fill in:
   - **Name:** `copilot-metrics-YOUR_ORG`
   - **Homepage URL:** `https://github.com/YOUR_ORG`
   - **Webhook:** UNCHECK "Active"
4. Under **"Organization permissions"** set:
   - **Organization Copilot metrics:** `Read-only` ✅
5. Select: **"Only on this account"**
6. Click **"Create GitHub App"**
7. **Copy the App ID** shown at the top
8. Scroll to **"Private keys"** → Click **"Generate a private key"** (downloads a .pem file)
9. Click **"Install App"** (left sidebar) → Install on your org
10. **Copy the Installation ID** from the URL (the number at the end)

### 3. Configure (2 minutes)

```bash
cd ~/Git/copilot-metrics-collector

# Run setup
./setup.sh

# Move private key
mv ~/Downloads/*.private-key.pem ./github-app-private-key.pem
chmod 600 ./github-app-private-key.pem

# Edit config
vim .env
```

**Edit these 4 values in `.env`:**

```bash
GITHUB_APP_ID=123456                  # Your App ID from step 2
GITHUB_INSTALLATION_ID=78901234       # Your Installation ID from step 2
GITHUB_PRIVATE_KEY_PATH=./github-app-private-key.pem
GITHUB_ORG=your-org-name              # Your GitHub org name
```

### 4. Run (30 seconds)

```bash
source .env
./capture-28day-metrics.sh
```

### 5. View Results

```bash
cat copilot-28day-*.txt
```

**Done!** 🎉

---

## 🏢 Enterprise Setup

For enterprises with multiple organizations:

### 1. Install jq (30 seconds)

Same as organization setup above.

### 2. Create GitHub App at Enterprise Level (5 minutes)

1. Go to: `https://github.com/enterprises/YOUR_ENTERPRISE/settings/apps`
2. Click **"New GitHub App"**
3. Fill in:
   - **Name:** `copilot-metrics-enterprise`
   - **Homepage URL:** `https://github.com/enterprises/YOUR_ENTERPRISE`
   - **Webhook:** UNCHECK "Active"
4. Under **"Enterprise permissions"** set:
   - **Enterprise Copilot metrics:** `Read-only` ✅
5. Click **"Create GitHub App"**
6. **Copy the App ID** shown at the top
7. Scroll to **"Private keys"** → Click **"Generate a private key"** (downloads a .pem file)
8. Click **"Install App"** → Install on your enterprise
9. **Copy the Installation ID** from the URL

### 3. Configure for Enterprise (2 minutes)

```bash
cd ~/Git/copilot-metrics-collector
./setup.sh

# Move private key
mv ~/Downloads/*.private-key.pem ./github-app-private-key.pem
chmod 600 ./github-app-private-key.pem

# Edit config
vim .env
```

**Edit these values in `.env` for enterprise:**

```bash
GITHUB_APP_ID=123456                       # Your Enterprise App ID
GITHUB_INSTALLATION_ID=78901234            # Your Enterprise Installation ID
GITHUB_PRIVATE_KEY_PATH=./github-app-private-key.pem
GITHUB_ENTERPRISE=your-enterprise-slug     # Your enterprise slug
```

### 4. Run Enterprise Scripts (30 seconds)

```bash
source .env

# Enterprise-wide 28-day summary
ENTERPRISE=true ./capture-28day-metrics.sh

# Enterprise user-level metrics (per-user breakdown across all orgs)
./capture-enterprise-users.sh

# Enterprise single-day aggregate
./capture-enterprise-metrics.sh
```

### 5. View Enterprise Results

```bash
cat copilot-enterprise-*.txt
```

**Done!** 🎉

---

## 📊 Available Scripts

### Organization Scripts

| Script | Use Case | Command |
|--------|----------|---------|
| **`capture-28day-metrics.sh`** | Last 28 days summary | `./capture-28day-metrics.sh` |
| `capture-org-metrics.sh` | Single day | `./capture-org-metrics.sh 2026-02-15` |
| `capture-team-metrics.sh` | Team-specific | `./capture-team-metrics.sh team-slug` |
| `capture-date-range-metrics.sh` | Custom trends | `./capture-date-range-metrics.sh 2026-02-01 2026-02-15` |

### Enterprise Scripts

| Script | Use Case | Command |
|--------|----------|---------|
| **`capture-28day-metrics.sh`** | Enterprise 28-day | `ENTERPRISE=true ./capture-28day-metrics.sh` |
| **`capture-enterprise-users.sh`** | Per-user breakdown | `./capture-enterprise-users.sh` |
| `capture-enterprise-metrics.sh` | Single day aggregate | `./capture-enterprise-metrics.sh 2026-02-15` |

---

## 🔄 Usage Examples

### Organization Examples
```bash
source .env

# Get 28-day summary (Recommended)
./capture-28day-metrics.sh

# Single day metrics
./capture-org-metrics.sh 2026-02-15

# Team metrics
./capture-team-metrics.sh backend-team

# Date range trends
./capture-date-range-metrics.sh 2026-02-01 2026-02-15
```

### Enterprise Examples
```bash
source .env

# Enterprise 28-day summary (all orgs aggregated)
ENTERPRISE=true ./capture-28day-metrics.sh

# Per-user metrics across entire enterprise
./capture-enterprise-users.sh

# Enterprise single day
./capture-enterprise-metrics.sh 2026-02-15

# With specific date
./capture-enterprise-users.sh 2026-02-12
```

---

## ✨ What You Get

### Output Formats

Every script generates **3 output files**:

1. **NDJSON** (`.ndjson`) - Raw per-user data from GitHub API
   - Newline-delimited JSON
   - Complete detailed metrics for each user
   - Perfect for data processing pipelines

2. **CSV** (`.csv`) - Spreadsheet-compatible format
   - Import into Excel, Google Sheets, or analytics tools
   - Columns: date, user_login, acceptances, suggestions, rates, lines, chats
   - Easy filtering and pivot tables

3. **TXT** (`.txt`) - Human-readable summary
   - Quick overview of key metrics
   - Formatted for terminal or reports
   - No tools required to read

**Example output files:**
```
copilot-metrics-acme-corp-2026-02-15.ndjson  ← Raw API data
copilot-metrics-acme-corp-2026-02-15.csv     ← Spreadsheet
copilot-metrics-acme-corp-2026-02-15.txt     ← Summary
```

### Organization Level
- **Org-wide metrics** - Total usage across organization
- **Team breakdowns** - Filter by specific teams
- **Daily/Monthly trends** - Track adoption over time

### Enterprise Level
- **Cross-org aggregation** - All organizations combined
- **Per-user metrics** - Individual productivity across all orgs
- **Enterprise trends** - Company-wide Copilot adoption

### All Levels Include
- **User engagement** - Who's using Copilot and how much
- **Code completion stats** - Suggestions, acceptances, rates
- **Model usage** - Which AI models (GPT-4, Claude, etc.)
- **IDE/Editor breakdown** - VS Code, JetBrains, etc.
- **Language statistics** - Python, JavaScript, TypeScript, etc.

Example TXT output:
```
Total Active Users: 247
Total Code Acceptances: 89,456
Total Suggestions: 123,789
Acceptance Rate: 72.27%
```

Example CSV format:
```csv
date,user_login,total_code_acceptances,total_code_suggestions,acceptance_rate,total_lines_accepted,total_lines_suggested,total_chats,copilot_ide_chat,copilot_dotcom_chat
2026-02-15,alice,145,200,72,287,412,23,23,0
2026-02-15,bob,234,310,75,456,598,57,45,12
2026-02-15,charlie,89,125,71,178,243,12,12,0
```

---

## 🤖 Automate Daily

### Organization
```bash
crontab -e
# Add: 0 2 * * * cd ~/Git/copilot-metrics-collector && source .env && ./capture-28day-metrics.sh >> logs/daily.log 2>&1
```

### Enterprise
```bash
crontab -e
# Add: 0 2 * * * cd ~/Git/copilot-metrics-collector && source .env && ENTERPRISE=true ./capture-28day-metrics.sh >> logs/daily.log 2>&1
```

---

## 🆘 Troubleshooting

| Problem | Solution |
|---------|----------|
| "Bad credentials" | Check `GITHUB_APP_ID` and `GITHUB_INSTALLATION_ID` in `.env` |
| "404 Not Found" | Check `GITHUB_ORG` or `GITHUB_ENTERPRISE` spelling |
| "403 Forbidden" | Verify app has correct permissions (see below) |
| "No download links" | Ensure metrics are enabled in settings |
| "jq not found" | Run: `brew install jq` |

Check config:
```bash
# Organization
source .env && echo "App: $GITHUB_APP_ID | Org: $GITHUB_ORG"

# Enterprise
source .env && echo "App: $GITHUB_APP_ID | Enterprise: $GITHUB_ENTERPRISE"
```

---

## 🔐 Required Permissions

### Organization GitHub App
- **Organization Copilot metrics:** Read-only ✅

### Enterprise GitHub App
- **Enterprise Copilot metrics:** Read-only ✅

*Note: These are the new permission names as of February 2026.*

---

## 📚 API Endpoints Used

### Organization
- `/orgs/{org}/copilot/metrics/reports/organization-28-day/latest`
- `/orgs/{org}/copilot/metrics/reports/organization-1-day?day=YYYY-MM-DD`

### Enterprise
- `/enterprises/{ent}/copilot/metrics/reports/enterprise-28-day/latest`
- `/enterprises/{ent}/copilot/metrics/reports/enterprise-1-day?day=YYYY-MM-DD`
- `/enterprises/{ent}/copilot/metrics/reports/users-1-day?day=YYYY-MM-DD` ⭐ Per-user

**Documentation:** https://docs.github.com/rest/copilot/copilot-usage-metrics

---

## 🎯 Which Setup Should I Use?

| Your Structure | Setup Type | Scripts to Use |
|----------------|------------|----------------|
| Single GitHub org | **Organization** | `capture-org-metrics.sh`, `capture-28day-metrics.sh` |
| Multiple orgs under enterprise | **Enterprise** | `capture-enterprise-*.sh`, `ENTERPRISE=true capture-28day-metrics.sh` |
| Want per-user data across enterprise | **Enterprise** | `capture-enterprise-users.sh` ⭐ |
| Want team-specific in one org | **Organization** | `capture-team-metrics.sh` |

---

**Simple. Fast. Complete.** 🚀 | Updated: February 17, 2026
