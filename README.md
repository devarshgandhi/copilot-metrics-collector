# GitHub Copilot Metrics Collector

**Collect GitHub Copilot usage metrics for your organization in 10 minutes.**

✨ **Updated February 2026** - Now using the latest GitHub Copilot Metrics API with enhanced data!

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
./capture-org-metrics.sh
```

### 5. View Results

```bash
cat copilot-metrics-*.txt
```

**Done!** 🎉

---

## ✨ What's New (February 2026 API)

This collector uses the **latest GitHub Copilot Metrics API** with enhanced data:

- ✅ **Model usage metrics** (GPT-4, Claude, etc.)
- ✅ **Per-user engagement data**
- ✅ **Enhanced IDE/Agent breakdown**
- ✅ **Language-specific metrics**
- ✅ **Up to 1 year of history** (vs 28 days with old API)
- ✅ **NDJSON format** for easier processing
- ✅ **Future-proof** (old API shut down April 2026)

---

## 📊 What You Get

Each run creates JSON output with comprehensive metrics:
- **User engagement data** - Who's using Copilot and how much
- **Code completion stats** - Suggestions, acceptances, rates
- **Model usage** - Which AI models are being used
- **IDE/Editor breakdown** - VS Code, JetBrains, etc.
- **Language statistics** - Python, JavaScript, TypeScript, etc.

Example:
```
Active Users: 247
Total Code Suggestions: 45,234
Total Acceptances: 32,891
Acceptance Rate: 72.71%

✨ Enhanced metrics including:
  - Model usage (GPT-4, Claude, etc.)
  - Per-user engagement data
  - IDE/Agent breakdown
  - Language-specific metrics
```

---

## 🔄 More Examples

```bash
# Yesterday's metrics
./capture-org-metrics.sh

# Specific date
./capture-org-metrics.sh 2024-12-15

# Multiple dates (run multiple times)
for date in 2024-12-{01..15}; do
  ./capture-org-metrics.sh $date
done
```

**Note:** The new API returns data for single days. For date ranges, run the script multiple times or use the 28-day endpoint (coming soon to this script).

---

## 🤖 Automate Daily

```bash
crontab -e
# Add: 0 2 * * * cd ~/Git/copilot-metrics-collector && source .env && ./capture-org-metrics.sh >> logs/daily.log 2>&1
```

---

## 🛠️ Available Scripts

| Script | Use Case | API Status |
|--------|----------|------------|
| `capture-org-metrics.sh` | Organization metrics | ✅ Updated to 2026 API |
| `capture-enterprise-metrics.sh` | Enterprise-wide | ⏳ Being updated |
| `capture-team-metrics.sh` | Team-specific | ⏳ Being updated |
| `capture-date-range-metrics.sh` | Trends | ⏳ Being updated |

---

## 🆘 Troubleshooting

| Problem | Solution |
|---------|----------|
| "Bad credentials" | Check `GITHUB_APP_ID` and `GITHUB_INSTALLATION_ID` in `.env` |
| "404 Not Found" | Check `GITHUB_ORG` spelling |
| "403 Forbidden" | Verify app has "Organization Copilot metrics: Read-only" permission (NEW permission name!) |
| "No download links" | Ensure metrics are enabled in org settings |
| "jq not found" | Run: `brew install jq` |

Check config:
```bash
source .env && echo "App: $GITHUB_APP_ID | Org: $GITHUB_ORG"
```

---

## 🔐 Required Permissions (Updated)

Your GitHub App needs:
- **Organization Copilot metrics:** Read-only ✅ (NEW - different from old "Copilot Business Metrics")

This is the new permission name as of February 2026.

---

## 📚 API Documentation

- **Latest API:** https://docs.github.com/rest/copilot/copilot-usage-metrics
- **Migration Guide:** See UPDATE_NOTICE.md
- **Old API (deprecated):** Being shut down April 2, 2026

---

**That's it! 🚀** | Updated: February 13, 2026 | Using latest GitHub API
