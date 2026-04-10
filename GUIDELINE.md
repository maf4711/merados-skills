# meradOS Guideline

Permanente, repo-uebergreifende Regeln fuer alle meradOS-Projekte.
Extrahiert aus: `merados`, `alpha-merados`, `meradOS-website`, `meradOS-Design`, `merados-portfolio`, `merados-skills`.

---

## 1. Philosophie: Elon 5-Schritt-Algorithmus

Jede Aufgabe durchlaeuft diese Reihenfolge — nie umgekehrt:

| # | Schritt | Regel |
|---|---------|-------|
| 1 | **Requirements hinterfragen** | Jede Anforderung braucht einen Namen (Person). Mindestens einmal zurueckweisen. |
| 2 | **Loeschen** | Jeden Teil/Prozess streichen der nicht absolut noetig ist. 10% wieder zurueckfuegen = richtig. |
| 3 | **Vereinfachen** | Erst NACH dem Loeschen. Nie optimieren was nicht existieren sollte. |
| 4 | **Beschleunigen** | Erst NACH dem Vereinfachen. Nie beschleunigen was geloescht werden sollte. |
| 5 | **Automatisieren** | Erst NACH dem Beschleunigen. Nie einen kaputten Prozess automatisieren. |

**Anwendung:**
- Code: Minimaler Code, maximale Wirkung. Keine Abstraktion ohne Grund.
- Planung: Kuerzester Weg zum Ziel. Unnoetige Schritte streichen.
- Probleme: First Principles — was ist physikalisch/logisch moeglich, nicht was "ueblich" ist.

---

## 2. Source of Truth

**Immer Live-Systeme abfragen, nie Dokumentation vertrauen:**

| Was | Wie |
|-----|-----|
| Datenbank | Supabase MCP oder `supabase db pull` |
| Infrastruktur | `aws ecs`, `vercel ls`, `cdk diff` |
| APIs | `curl -v` fuer echte Responses |
| Deployments | `cdk diff` vor `cdk deploy` |

---

## 3. TypeScript Standards

Gilt fuer: `merados`, `alpha-merados`, `meradOS-website`, `meradOS-Design`

### Compiler
```jsonc
{
  "compilerOptions": {
    "strict": true,
    "target": "ES2020",          // minimum, ES2022 fuer Node-Projekte
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "declaration": true,
    "sourceMap": true,
    "paths": { "@/*": ["./*"] }  // Standard-Alias
  }
}
```

### ESLint
```jsonc
// Flat config (eslint.config.mjs)
{
  "rules": {
    "@typescript-eslint/no-unused-vars": ["warn", { "argsIgnorePattern": "^_" }],
    "@typescript-eslint/no-explicit-any": "warn"
  }
}
// Legacy (.eslintrc.json) — extends: ["next/core-web-vitals", "next/typescript"]
```

**Keine Prettier** — ESLint reicht. Kein Biome. Kein EditorConfig.

---

## 4. Python Standards

Gilt fuer: `merados`, `merados-portfolio`

### Ruff (einziger Linter/Formatter)
```toml
[tool.ruff]
line-length = 120
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "W", "I"]

[tool.ruff.lint.isort]
known-first-party = ["connectors", "dashboard", "models", "aggregator", "database"]
```

**Auto-Format Hook** (aus merados `.claude/settings.json`):
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "command": "ruff format $FILE && ruff check --fix $FILE"
    }]
  }
}
```

### Testing
- **Framework:** pytest mit pytest-cov
- **Coverage-Minimum:** 40%
- **Scope:** Proportional zur Aenderung, nie pauschal full suite
- **Bug-Workflow:** Reproduzierender Test zuerst → Fix → Test muss gruen sein

---

## 5. Design System (@merados/design-system v3)

Quelle: `meradOS-Design` — NPM-Package mit Tailwind-Preset, CSS-Tokens, Swift-Support.

### Farben
| Token | Verwendung |
|-------|------------|
| `brand-50..900` | Primaerfarbe (Sky Blue Gradient) |
| `navy-800/900/950` | Dunkle Hintergruende |
| `surface-elevated/overlay` | Karten, Modals |
| `dataviz-1..6` | Chart-Farben |
| `status-success/warning/error/info` | Feedback |

### Typografie
- **Sans:** Inter, -apple-system, SF Pro Display
- **Mono:** SF Mono, Fira Code, monospace
- **Logo:** SF Pro Display, Inter, system-ui

### Border Radius
| Token | Wert |
|-------|------|
| `sm` | 8px |
| `md` | 12px |
| `lg` | 16px |
| `xl` | 22px |

### Motion
| Token | Wert |
|-------|------|
| `duration-instant` | 100ms |
| `duration-fast` | 150ms |
| `duration-normal` | 250ms |
| `duration-slow` | 400ms |
| `easing-standard` | cubic-bezier(0.4, 0, 0.2, 1) |
| `easing-enter` | cubic-bezier(0, 0, 0.2, 1) |
| `easing-exit` | cubic-bezier(0.4, 0, 1, 1) |

### Dark Mode
Default. Light Mode via `data-theme="light"`. Reduced-motion Support eingebaut.

### Integration
```ts
// tailwind.config.ts
import { preset } from '@merados/design-system/tailwind'
export default { presets: [preset] }

// globals.css
@import '@merados/design-system/globals.css'
```

---

## 6. CI/CD Patterns

### GitHub Actions — Standard-Pipeline
```yaml
# Alle Repos:
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

# Node-Version: 22 (website) oder 20 (backend)
# Python-Version: 3.13
```

### Test-Scope nach Branch
| Trigger | Scope |
|---------|-------|
| PR → main | ALL (unit + integration + E2E) |
| PR → dev | unit + integration |
| Feature-Branch push | unit only |

### Claude-Branch Automation (Website-Pattern)
1. Push auf `claude/**` Branch
2. Auto-PR erstellen
3. Lint → Type-Check → Build
4. Auto-Squash-Merge bei Erfolg

### Error Triage (merados-Pattern)
- Taeglich 07:00 UTC: Supabase-Errors der letzten 24h abfragen
- GitHub Issue erstellen mit Triage
- Claude analysiert: Code-Bug vs Runtime/Data
- Fix-Branch bei Code-Bugs

### Litmus Health Check
- Taeglich 06:00 UTC mit echten API-Keys
- Failure-Notification per Script

### Vercel Deployment
- **Production:** Push auf `main` → Vercel CLI build + deploy (`--prebuilt --prod`)
- **Preview:** PR → Vercel preview deploy + PR-Comment mit URL
- **Secrets:** `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`
- **Concurrency:** `cancel-in-progress: false` fuer Production (kein Abbruch laufender Deploys)
- **Cron Jobs:** In `vercel.json` definiert (alpha-merados hat 22 Cron-Endpoints)
- **Pattern:** Vercel fuer Frontend/Crons, AWS fuer Backend/Long-Running

### Vercel Cron Conventions (alpha-merados)
| Frequenz | Beispiele |
|----------|-----------|
| `*/5 * * * 1-5` | Trade-Alerts (alle 5 Min, Mo-Fr) |
| `*/30 * * * 1-5` | System-Health |
| `0 */2 * * 1-5` | Alerts (alle 2h) |
| `0 9 * * 1-5` | Taeglich morgens (Rankings, Errors, Live-Depots) |
| `0 18 * * 5` | Woechentlich Freitag (Recap, Experiments) |
| `30 6 * * 1` | Woechentlich Montag (Newsletter) |

---

## 7. Infrastruktur-Stack

| Layer | Technologie | Repo |
|-------|------------|------|
| Frontend (Dashboard) | Next.js + Vercel | alpha-merados |
| Website | Next.js 14 + Vercel | meradOS-website |
| Backend APIs | AWS Lambda (Python) | merados |
| Long-Running | AWS ECS | merados |
| Database | Supabase (PostgreSQL) | merados |
| IaC | AWS CDK (Python) | merados |
| Design System | NPM Package + Swift | meradOS-Design |
| Portfolio CLI | Python 3.12 | merados-portfolio |
| Mobile | Expo/React Native 0.83 | merados (subfolder) |

### Supabase
- **Project ID:** `yzdidzkgwgelnwrincrj`
- **Dashboard:** Read-only mit anon key + RLS
- **Backend:** Service role key fuer Writes

### Vercel
- Website: `merados.com`
- Dashboard: Separate Vercel-Projekte

---

## 8. Git Conventions

### Branch-Naming
- `claude/**` — AI-generierte Branches (Auto-PR/Merge)
- `feature/**` — manuelle Feature-Branches
- `main` — Production
- `dev` — Staging (merados)

### Gitignore — Immer ignorieren
```
.env, .env*.local
node_modules/
__pycache__/, *.pyc
.DS_Store
dist/, .next/, cdk.out/
*.db, *.log, *.bak
.venv/
```

### Gitignore — Nie ignorieren
```
requirements.txt
forecasting experiment files
```

---

## 9. Dev-Tools (Tier-System)

Aus merados-desktop Skill:

| Tier | Tool | Ersetzt |
|------|------|---------|
| **1 MUST** | `eza` | `ls` |
| **1 MUST** | `bat` | `cat` |
| **1 MUST** | `fd` | `find` |
| **1 MUST** | `rg` | `grep` |
| **1 MUST** | `fzf` | fuzzy search |
| **1 MUST** | `zoxide` | `cd` |
| **1 MUST** | `delta` | `diff` |
| 2 SOLL | `tldr` | `man` |
| 2 SOLL | `httpie` | `curl` |
| 2 SOLL | `jq` | JSON processing |
| 3 KANN | `hyperfine` | benchmarking |
| 3 KANN | `dust` | `du` |
| 3 KANN | `procs` | `ps` |

---

## 10. Experiment-Konventionen (Trading)

- Einzigartige YAML-Dateinamen
- Deskriptive Namen
- Split-Test gegen letzten Gewinner
- Nie laufende Experimente modifizieren
- `trading_timestamp: datetime` ist kanonisch, wird am Entry Point gesetzt

---

## 11. Slack-Automation Regeln

Aus merados-slack-advisor Skill:

1. **Max 4 Channels:** critical, deploy, daily-digest, weekly-report
2. **Nie senden:** Commits, Erfolge, Build-Start, PR-Opened
3. **Immer senden:** Errors, Deploy-Failures, Security-Alerts, Budget-Alerts
4. **Webhook > Bot > App** (einfachste Loesung zuerst)
5. **Rate-Limit:** Max 1 Message/Minute pro Channel
6. **Deduplizierung:** Gleiche Errors nur 1x pro Stunde

---

## 12. Security

- Keine `.env`-Dateien committen
- API-Keys immer in `.env` oder Secrets Manager
- Worktrees brauchen symlinked `.env`
- IaC-Validation: CDK synth + cfn-lint + Checkov
- `powered-by` Header deaktivieren (Next.js)
- Image-Optimization: AVIF + WebP
