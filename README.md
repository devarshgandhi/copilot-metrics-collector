# GitHub Copilot Metrics Collector

**Collect GitHub Copilot usage metrics for your organization in 10 minutes.**

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
   - **Copilot Business Metrics:** `Read-only`
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
./capture-org-metrics.sh
```

### 5. View Results

```bash
cat copilot-metrics-*.txt
```

**Done!** 🎉

---

## 📊 What You Get

Each run creates 3 files:
- **`.json`** - Raw data
- **`.txt`** - Human-readable report
- **`.csv`** - Excel/Google Sheets

Example:
```
Active Users: 247
Suggestions: 45,234
Acceptances: 32,891
Acceptance Rate: 72.71%
```

---

## 🔄 More Examples

```bash
# Yesterday's metrics
./capture-org-metrics.sh

# Specific date
./capture-org-metrics.sh 2024-12-15

# Date range
./capture-org-metrics.sh 2024-12-01 2024-12-15

# Last 4 weeks with trends
./capture-date-range-metrics.sh --period weekly --weeks 4 --show-trends
```

---

## 🤖 Automate Daily

```bash
crontab -e
# Add: 0 2 * * * cd ~/Git/copilot-metrics-collector && source .env && ./capture-org-metrics.sh >> logs/daily.log 2>&1
```

---

## 🛠️ Available Scripts

| Script | Use Case |
|--------|----------|
| `capture-org-metrics.sh` | Organization metrics |
| `capture-enterprise-metrics.sh` | Enterprise-wide |
| `capture-team-metrics.sh` | Team-specific |
| `capture-date-range-metrics.sh` | Trends |

---

## 🆘 Troubleshooting

| Problem | Solution |
|---------|----------|
| "Bad credentials" | Check `GITHUB_APP_ID` and `GITHUB_INSTALLATION_ID` in `.env` |
| "404 Not Found" | Check `GITHUB_ORG` spelling |
| "403 Forbidden" | Verify app has "Copilot Business Metrics: Read-only" permission |
| "No data" | Use yesterday or earlier |
| "jq not found" | Run: `brew install jq` |

Check config:
```bash
source .env && echo "App: $GITHUB_APP_ID | Org: $GITHUB_ORG"
```

---

**That's it! 🚀** | More info: https://docs.github.com/en/rest/copilot/copilot-usage
