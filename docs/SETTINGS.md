# FS25_UsedPlus Settings & Toggles

**Version:** 1.9.8+
**Last Updated:** 2026-01-01

This document defines the configurable settings for UsedPlus. The focus is on **system toggles** (on/off) plus a small set of impactful economic parameters.

---

## Table of Contents

1. [Settings Overview](#settings-overview)
2. [System Toggles (7 total)](#system-toggles)
3. [Economic Settings (15 total)](#economic-settings)
4. [Preset Configurations](#preset-configurations)
5. [Multiplayer Considerations](#multiplayer-considerations)

---

## Settings Overview

UsedPlus settings are designed to be **simple but powerful**:

- **9 System Toggles**: Enable/disable major features independently
- **15 Economic Parameters**: Tune difficulty and realism
- **4 Presets**: Quick configurations for different playstyles

**Total: ~24 settings** (not 100!)

### Settings Location

- **ESC Menu → Settings**: System toggles only
- **Finance Manager → Settings**: All settings with presets

### Settings Persistence

- Saved to `savegame/usedplus_settings.xml`
- Server authority in multiplayer (master rights required)

---

## System Toggles

These master switches enable/disable entire features. **This is where most players will interact with settings.**

| # | Toggle | Default | What It Controls |
|---|--------|---------|------------------|
| 1 | **Finance System** | ON | Vehicle/equipment/land loans |
| 2 | **Lease System** | ON | Lease-to-own options |
| 3 | **Used Vehicle Search** | ON | Marketplace for used equipment |
| 4 | **Vehicle Sale System** | ON | List vehicles for sale via agents |
| 5 | **Repair System** | ON | Partial repair, paint, parts |
| 6 | **Trade-In System** | ON | Trade old equipment on purchases |
| 7 | **Credit System** | ON | Credit scoring affects rates |
| 8 | **Tire Wear System** | ON | Realistic tire degradation over time |
| 9 | **Malfunctions System** | ON | Random breakdowns & component failures |

### System Dependencies

```
Finance System
  └── Credit System (if OFF → flat interest rates)
  └── Trade-In System (if OFF → cash only, no trade)

Used Vehicle Search
  └── Finance System (if OFF → cash purchases only)

Lease, Sale, Repair → No dependencies
```

**Use Case Examples:**
- *"I just want loans, nothing fancy"* → Turn OFF: Search, Sale, Repair, Trade-In
- *"Another mod handles repairs"* → Turn OFF: Repair System
- *"I hate credit scores"* → Turn OFF: Credit System (flat 8% rates)
- *"Breakdowns are annoying"* → Turn OFF: Malfunctions System
- *"I use Real Vehicle Breakdowns mod"* → Turn OFF: Tire Wear, Malfunctions

---

## Economic Settings

These tune the difficulty. Organized by what players actually care about.

### Money & Rates (4 settings)

| Setting | Default | Range | Impact |
|---------|---------|-------|--------|
| **Base Interest Rate** | 8% | 3-15% | Higher = harder to afford loans |
| **Trade-In Value** | 55% | 40-70% | Higher = more value for old equipment |
| **Repair Cost Multiplier** | 1.0x | 0.5-2.0x | Higher = expensive repairs |
| **Lease Markup** | 15% | 5-30% | Higher = leasing costs more |

### Forgiveness & Risk (4 settings)

| Setting | Default | Range | Impact |
|---------|---------|-------|--------|
| **Missed Payments to Default** | 3 | 1-6 | Lower = less room for error |
| **Min Down Payment** | 0% | 0-30% | Higher = need more cash upfront |
| **Starting Credit Score** | 650 | 500-750 | Lower = worse initial rates |
| **Late Payment Penalty** | -15 pts | -5 to -30 | Higher = credit drops faster |

### Marketplace Tuning (4 settings)

| Setting | Default | Range | Impact |
|---------|---------|-------|--------|
| **Search Success Rate** | 75% | 50-95% | Lower = harder to find used |
| **Max Listings Per Farm** | 3 | 1-10 | How many vehicles you can sell at once |
| **Offer Expiration** | 48 hrs | 24-168 | Time to accept buyer offers |
| **Agent Commission** | 8% | 3-15% | Cost to use sale agents |

### Condition & Quality (3 settings)

| Setting | Default | Range | Impact |
|---------|---------|-------|--------|
| **Used Vehicle Condition Range** | 40-95% | 20-100% | Quality of found used vehicles |
| **Condition Price Impact** | 1.0x | 0.5-1.5x | How much condition affects value |
| **Brand Loyalty Bonus** | 5% | 0-15% | Trade-in bonus for same brand |

---

## Preset Configurations

One-click configurations for common playstyles.

### Realistic (Default)
*Balanced simulation - the intended experience*
- All systems ON
- Default values for everything

### Casual
*Relaxed economics - focus on farming, not spreadsheets*
- Credit System OFF (flat rates)
- Interest Rate: 5%
- Missed Payments: 6 (very forgiving)
- Trade-In Value: 65%
- Search Success: 90%

### Hardcore
*Punishing economics - every dollar matters*
- Interest Rate: 12%
- Missed Payments: 2
- Min Down Payment: 20%
- Starting Credit: 550
- Trade-In Value: 45%
- Late Payment Penalty: -25 pts

### Lite Mode
*Just the basics - finance and lease only*
- Used Search OFF
- Vehicle Sale OFF
- Repair System OFF
- Trade-In OFF
- Only Finance + Lease + Credit active

---

## Multiplayer Considerations

### Who Can Change Settings?

| Setting Type | Authority |
|--------------|-----------|
| All toggles & economic settings | Server admin (master rights) |
| Credit scores | Per-farm (not a setting) |

### What Syncs?

- Settings sync to all players on join
- Changes broadcast immediately
- Non-admins see settings but can't change them

---

## Quick Reference Card

**System Toggles (9):**
Finance, Lease, Used Search, Vehicle Sale, Repair, Trade-In, Credit, Tire Wear, Malfunctions

**Key Economic Knobs (6 most impactful):**
1. Interest Rate (3-15%)
2. Missed Payments to Default (1-6)
3. Trade-In Value (40-70%)
4. Starting Credit Score (500-750)
5. Search Success Rate (50-95%)
6. Repair Cost Multiplier (0.5-2.0x)

**Presets:** Realistic, Casual, Hardcore, Lite Mode
