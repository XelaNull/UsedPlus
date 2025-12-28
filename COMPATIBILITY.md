# FS25_UsedPlus - Cross-Mod Compatibility Guide

**Last Updated:** 2025-12-28
**Version:** 1.8.2 (Deep Integration)

This document analyzes compatibility between UsedPlus and popular FS25 mods that players commonly run together.

---

## Quick Reference

| Mod | Status | Summary |
|-----|--------|---------|
| **CrudeOilProduction** | COMPATIBLE | Pure production mod, no conflicts |
| **SpecialOffers** | COMPATIBLE | Notification utility, no conflicts |
| **Real Vehicle Breakdowns** | INTEGRATED | UsedPlus provides "symptoms before failure" |
| **Use Up Your Tyres** | INTEGRATED | Tire condition syncs, flat tire deferred |
| **EnhancedLoanSystem** | INTEGRATED | ELS loans display in Finance Manager with Pay Early support |
| **BuyUsedEquipment** | COMPATIBLE | UsedPlus hides search button when BUE detected |
| **HirePurchasing** | INTEGRATED | HP leases display in Finance Manager |
| **AdvancedMaintenance** | COMPATIBLE | Both maintenance systems work together |
| **Employment** | INTEGRATED | Worker wages included in monthly obligations |

---

## Fully Compatible Mods

### CrudeOilProduction

**Status:** FULLY COMPATIBLE

**What it does:** Adds crude oil extraction and refining production chain (oil wells, refineries, selling stations). Pure XML-defined placeable mod with no Lua scripts.

**Why it works:**
- No game hooks or function overrides
- Adds new placeables that can be financed through UsedPlus
- New vehicles integrate with UsedPlus used market naturally
- Different systems - no overlap

**Synergies:**
- Finance oil infrastructure with UsedPlus loans
- Oil equipment creates income to pay off loans
- Higher upkeep costs create financial pressure (realistic gameplay)

---

### SpecialOffers

**Status:** FULLY COMPATIBLE

**What it does:** Notification utility that alerts players when new vehicles appear in the shop sale system.

**Why it works:**
- Read-only access to shop data
- No function hooks or overrides
- Only subscribes to `HOUR_CHANGED` event (safe - multiple subscribers allowed)
- Creates only its own `SpecialOffers.*` namespace

**Synergies:**
- Get notified when new used vehicles appear
- Then finance them through UsedPlus

---

## Integrated Mods (Enhanced Cooperation)

### Real Vehicle Breakdowns (RVB)
**Author:** MathiasHun

**Status:** INTEGRATED (v1.8.0+)

**What it does:** Comprehensive vehicle breakdown simulation tracking 10+ parts with operating hours and failure states.

**How UsedPlus integrates:**
- **"Symptoms Before Failure"** - UsedPlus provides gradual degradation symptoms (speed limiting, stalling, steering pull) that warn players BEFORE RVB triggers catastrophic failure
- **Reliability Derivation** - UsedPlus reads RVB part health to calculate symptom severity
- **OBD Repair Integration** - Field Service Kit successful diagnoses reduce RVB operating hours
- **Unique Features Preserved** - Hydraulic drift and steering pull remain unique to UsedPlus (RVB doesn't track hydraulics)

**What happens with both installed:**
| Feature | Who Handles It |
|---------|---------------|
| Progressive speed limiting | UsedPlus (uses RVB engine health) |
| First-start stalling | UsedPlus (uses RVB engine health) |
| Hydraulic drift | UsedPlus only (unique feature) |
| Steering pull | UsedPlus only (unique feature) |
| Final engine failure | RVB (7 km/h cap when part exhausted) |
| Final electrical failure | RVB (lights/starter fail) |
| Flat tire trigger | RVB (via UYT integration) |

---

### Use Up Your Tyres (UYT)
**Author:** 50keda

**Status:** INTEGRATED (v1.8.0+)

**What it does:** Distance-based tire wear system with visual progression and friction reduction.

**How UsedPlus integrates:**
- **Tire Condition Sync** - UsedPlus reads UYT wear data to update tire condition displays
- **Flat Tire Deferral** - UsedPlus skips its own flat tire trigger when UYT is installed
- **Low Traction Warnings** - UsedPlus still shows traction warnings based on synced condition

**What happens with both installed:**
| Feature | Who Handles It |
|---------|---------------|
| Tire wear calculation | UYT (distance-based) |
| Visual tire degradation | UYT (shader-based) |
| Tire condition display | UsedPlus (synced from UYT) |
| Flat tire trigger | UYT/RVB |
| Low traction warning | UsedPlus |
| Tire replacement | UYT (workshop button) |

---

## Compatible Mods (Feature Deferral)

These mods were previously marked as "conflicting" but are now **fully compatible** as of v1.8.1. UsedPlus automatically detects them and defers specific features to avoid conflicts.

### EnhancedLoanSystem (ELS)

**Status:** INTEGRATED (v1.8.2+)

**What it does:** Replaces vanilla loan system with annuity-based loans featuring collateral requirements, variable interest rates, and monthly payments.

**How UsedPlus integrates:**
- **Detection:** `g_els_loanManager ~= nil`
- **Finance Manager Display** - ELS loans appear in the Active Finances table with "ELS" type marker
- **Pay Early Button** - Make payments on ELS loans directly from UsedPlus Finance Manager
- **Monthly Totals** - ELS loan payments included in monthly obligations display
- **Debt Totals** - ELS loan balances included in total debt calculation
- **Take Loan button** - Hidden (ELS handles loan creation)
- **Cash loan creation** - Blocked (ELS handles all loans)

**What happens with both installed:**
| Feature | Who Handles It |
|---------|---------------|
| Cash loans (creation) | ELS |
| Loan display in Finance Manager | UsedPlus (reads ELS data) |
| Loan payments via Pay Early | UsedPlus (calls ELS API) |
| Vehicle financing | UsedPlus |
| Vehicle leasing | UsedPlus |
| Used vehicle search | UsedPlus |
| Agent-based sales | UsedPlus |
| Maintenance & symptoms | UsedPlus |
| Credit scoring | Both (independent) |

**Unified Financial View:**
Players see ALL their financial obligations in one place - UsedPlus deals AND ELS loans together in the Finance Manager.

---

### BuyUsedEquipment (BUE)

**Status:** COMPATIBLE (v1.8.1+)

**What it does:** Broker-based used equipment search where players pay a fee, wait for success rolls, and find vehicles in the vanilla shop's Sales tab.

**How UsedPlus handles compatibility:**
- **Detection:** `BuyUsedEquipment ~= nil`
- **Search Used button** - Hidden from shop when BUE detected
- **UsedVehicleManager** - Still initializes (for agent-based selling)
- **Financing** - Still works for all purchases including BUE finds
- **Agent-based sales** - Still works (selling your equipment)

**What happens with both installed:**
| Feature | Who Handles It |
|---------|---------------|
| Used vehicle search | BUE |
| Search button in shop | BUE |
| Vehicle financing | UsedPlus |
| Vehicle leasing | UsedPlus |
| Agent-based sales | UsedPlus |
| Maintenance & symptoms | UsedPlus |

---

### HirePurchasing (HP)

**Status:** INTEGRATED (v1.8.2+)

**What it does:** Hire purchase financing with deposit requirements, 1-10 year terms, and optional balloon payments.

**How UsedPlus integrates:**
- **Detection:** `g_currentMission.LeasingOptions ~= nil`
- **Finance Manager Display** - HP leases appear in the Active Finances table with "HP" type marker
- **Info Dialog** - Click Pay Early on HP leases to see details (HP manages payments automatically)
- **Monthly Totals** - HP lease payments included in monthly obligations display
- **Debt Totals** - HP lease balances included in total debt calculation
- **Finance button** - Hidden from shop (HP handles financing)

**What happens with both installed:**
| Feature | Who Handles It |
|---------|---------------|
| Vehicle financing (hire purchase) | HP |
| Finance button in shop | HP |
| Lease display in Finance Manager | UsedPlus (reads HP data) |
| Automatic lease payments | HP (hourly processing) |
| Vehicle leasing | UsedPlus |
| Used vehicle search | UsedPlus |
| Agent-based sales | UsedPlus |
| Maintenance & symptoms | UsedPlus |

**Note:** HP manages lease payments automatically each hour. UsedPlus displays HP leases for visibility but doesn't process HP payments directly.

---

### AdvancedMaintenance (AM)

**Status:** COMPATIBLE (v1.8.1+)

**What it does:** Prevents engine start at 0% damage and causes random shutdowns when damage exceeds 28%.

**How UsedPlus handles compatibility:**
- **Detection:** Specialization registry check + `AdvancedMaintenance ~= nil`
- **Function chaining** - UsedPlus calls AM's damage check in `getCanMotorRun` chain
- **Both systems active** - UsedPlus symptoms + AM damage-based failures

**What happens with both installed:**
| Feature | Who Handles It |
|---------|---------------|
| Progressive speed limiting | UsedPlus (reliability-based) |
| First-start stalling | UsedPlus (reliability-based) |
| Hydraulic drift | UsedPlus |
| Steering pull | UsedPlus |
| Engine block at 0% damage | AM |
| Random shutdown >28% damage | AM |
| Overheating symptoms | UsedPlus |
| Electrical symptoms | UsedPlus |

**The best of both worlds:**
- UsedPlus provides gradual symptoms as components degrade
- AM provides damage-based catastrophic failures
- Together: realistic progression from "engine struggling" to "engine won't start"

---

### Employment

**Status:** INTEGRATED (v1.8.2+)

**What it does:** Adds worker hiring system with wages and productivity bonuses.

**How UsedPlus integrates:**
- **Detection:** `g_currentMission.employmentSystem ~= nil`
- **Monthly Totals** - Worker wages automatically included in monthly obligations
- **Visual Indicator** - Asterisk (*) shown on monthly total when wages are included
- **Budget Planning** - See true monthly costs including labor

**What happens with both installed:**
| Feature | Who Handles It |
|---------|---------------|
| Worker hiring/management | Employment |
| Wage payments | Employment |
| Wage display in monthly total | UsedPlus |
| Budget visibility | UsedPlus Finance Manager |

**Financial Clarity:**
When Employment mod is installed, your monthly obligations in Finance Manager include:
- Loan payments (UsedPlus + ELS)
- Lease payments (UsedPlus + HP)
- Worker wages (Employment)

This gives you a complete picture of your farm's monthly cash requirements.

---

## Technical Details

### Detection Methods Used by UsedPlus

```lua
-- Integrated mods
ModCompatibility.rvbInstalled = g_currentMission.vehicleBreakdowns ~= nil
ModCompatibility.uytInstalled = UseYourTyres ~= nil

-- Compatible mods (feature deferral)
ModCompatibility.advancedMaintenanceInstalled = AdvancedMaintenance ~= nil
ModCompatibility.hirePurchasingInstalled = g_currentMission.LeasingOptions ~= nil
ModCompatibility.buyUsedEquipmentInstalled = BuyUsedEquipment ~= nil
ModCompatibility.enhancedLoanSystemInstalled = g_els_loanManager ~= nil
```

### Feature Availability Queries

```lua
-- Check if UsedPlus should show its buttons/features
ModCompatibility.shouldShowFinanceButton()    -- false if HP detected
ModCompatibility.shouldShowSearchButton()     -- false if BUE detected
ModCompatibility.shouldShowTakeLoanOption()   -- false if ELS detected
ModCompatibility.shouldEnableLoanSystem()     -- false if ELS detected
```

### Data Access Functions (v1.8.2+)

```lua
-- ELS Integration
ModCompatibility.getELSLoans(farmId)          -- Returns pseudo-deal array for display
ModCompatibility.payELSLoan(pseudoDeal, amt)  -- Make payment via ELS API

-- HP Integration
ModCompatibility.getHPLeases(farmId)          -- Returns pseudo-deal array for display
ModCompatibility.payHPLease(pseudoDeal, amt)  -- Attempt payment (HP manages automatically)
ModCompatibility.settleHPLease(pseudoDeal)    -- Early settlement

-- Employment Integration
ModCompatibility.getEmploymentMonthlyCost(playerId)  -- Worker wages per month

-- Farmland Integration
ModCompatibility.getFarmlandValue(farmId)     -- Total value of owned farmland
ModCompatibility.getFarmlandCount(farmId)     -- Number of owned fields

-- Aggregate Functions
ModCompatibility.getExternalMonthlyObligations(farmId)  -- ELS + HP monthly total
ModCompatibility.getExternalTotalDebt(farmId)           -- ELS + HP debt total
```

### Key UsedPlus Hooks

| Function | Hook Type | Purpose |
|----------|-----------|---------|
| `Farm.new` | overwrittenFunction | Finance data initialization |
| `Farm.saveToXMLFile` | appendedFunction | Persist finance deals |
| `Farm.loadFromXMLFile` | overwrittenFunction | Load finance deals |
| `ShopConfigScreen.setStoreItem` | appendedFunction | Add Finance/Search buttons |
| `BuyVehicleData.buy` | overwrittenFunction | Intercept purchases |
| `Vehicle.showInfo` | appendedFunction | Display finance info |
| `getCanMotorRun` | registerOverwrittenFunction | Engine stall/governor (chains to AM) |

---

## Recommendations for Players

### Best Experience (Recommended Setup)
- **UsedPlus** (financial system, maintenance, marketplace)
- **Real Vehicle Breakdowns** (catastrophic failures)
- **Use Up Your Tyres** (visual tire wear)
- **Employment** (worker management with wages in Finance Manager)
- **CrudeOilProduction** (production chain)
- **SpecialOffers** (shop notifications)

### All Mods Now Compatible
As of v1.8.2, UsedPlus is **deeply integrated** with popular financial/maintenance mods:
- **EnhancedLoanSystem** - Loans display in Finance Manager, Pay Early works
- **HirePurchasing** - Leases display in Finance Manager for unified view
- **Employment** - Worker wages included in monthly obligations
- **BuyUsedEquipment** - Use BUE for search, UsedPlus for financing/sales
- **AdvancedMaintenance** - Both maintenance systems work together

### Mix and Match
You can now run any combination:
- UsedPlus + ELS + HP + Employment = **Unified Financial Dashboard**
- See ALL your obligations in one place: loans, leases, financing, wages
- Each mod handles its specialty, UsedPlus provides the unified view

---

## Version History

**2025-12-28 (v1.8.2)** - Deep Integration
- ELS loans now display in Finance Manager with "ELS" type marker
- HP leases now display in Finance Manager with "HP" type marker
- Pay Early button works with ELS loans (calls ELS payment API)
- Employment wages included in monthly obligations total
- Farmland count shown in assets display
- Added data access functions for cross-mod integration
- Updated ELS/HP status from COMPATIBLE to INTEGRATED

**2025-12-28 (v1.8.1)** - Extended compatibility
- All previously conflicting mods now COMPATIBLE
- Added automatic mod detection via ModCompatibility.init()
- Added feature deferral for ELS, BUE, HP, AM
- Added function chaining for AM's getCanMotorRun
- Updated quick reference table

**2025-12-28 (v1.8.0)** - Initial compatibility documentation
- Analyzed 6 popular mods for conflicts
- Documented RVB/UYT integration
- Created quick reference table
