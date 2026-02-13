# GitHub Copilot Metrics Collector

**Collect GitHub Copilot usage metrics for your organization in 10 minutes.**

✨ **Updated February 2026** - Using latest GitHub Copilot Metrics API

---

## 🚀 Quick Setup

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

## 📊 Available Scripts

| Script | Use Case | When to Use |
|--------|----------|-------------|
| **`capture-28day-metrics.sh`** | Last 28 days summary | **Recommended** - Complete monthly overview |
| `capture-org-metrics.sh` | Single day | Specific date analysis |
| `capture-enterprise-metrics.sh` | Enterprise-wide | Multiple orgs |
| `capture-team-metrics.sh` | Team-specific | Filter by team |
| `capture-date-range-metrics.sh` | Custom trends | Historical analysis |

---

## 🔄 Usage Examples

### Get 28-Day Summary (Recommended)
```bash
source .env
./capture-28day-metrics.sh
```

### Single Day Metrics
```bash
source .env
./capture-org-metrics.sh 2024-12-15
```

### Enterprise Metrics
```bash
source .env
ENTERPRISE=true ./capture-28day-metrics.sh
```

### Team Metrics
```bash
source .env
./capture-team-metrics.sh my-team-slug
```

### Date Range Trends
```bash
source .env
./capture-date-range-metrics.sh 2024-12-01 2024-12-15
```

---

## ✨ What You Get

Each run creates JSON output with comprehensive metrics:
- **User engagement data** - Who's using Copilot and how much
- **Code completion stats** - Suggestions, acceptances, rates
- **Model usage** - Which AI models are being used
- **IDE/Editor breakdown** - VS Code, JetBrains, etc.
- **Language statistics** - Python, JavaScript, TypeScript, etc.

Example output:
```
Total Active Users: 247
Total Code Acceptances: 32,891
Total Suggestions: 45,234
Acceptance Rate: 72.71%

✨ 28-day report includes:
  - Complete 28-day user activity
  - Model usage trends
  - Daily engagement patterns
```

---

## 🤖 Automate Daily

```bash
crontab -e
# Add: 0 2 * * * cd ~/Git/copilot-metrics-collector && source .env && ./capture-28day-metrics.sh >> logs/daily.log 2>&1
```

---

## 🆘 Troubleshooting

| Problem | Solution |
|---------|----------|
| "Bad credentials" | Check `GITHUB_APP_ID` and `GITHUB_INSTALLATION_ID` in `.env` |
| "404 Not Found" | Check `GITHUB_ORG` spelling |
| "403 Forbidden" | Verify app has "Organization Copilot metrics: Read-only" permission |
| "No download links" | Ensure metrics are enabled in org settings |
| "jq not found" | Run: `brew install jq` |

Check config:
```bash
source .env && echo "App: $GITHUB_APP_ID | Org: $GITHUB_ORG"
```

---

## 🔐 Required Permissions

Your GitHub App needs:
- **Organization Copilot metrics:** Read-only ✅

---

## 📚 API Documentation

- **Latest API:** https://docs.github.com/rest/copilot/copilot-usage-metrics
- **API Version:** 2022-11-28

---

**Simple. Fast. Up-to-date.** 🚀 | Updated: February 13, 2026
