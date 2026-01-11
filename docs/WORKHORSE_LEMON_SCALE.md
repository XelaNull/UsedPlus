# Workhorse/Lemon Scale System

**Version:** 2.2.0
**Last Updated:** 2026-01-11
**Status:** IMPLEMENTED (Lua complete, RVB integration complete, translations pending)
**Purpose:** Add permanent vehicle "DNA" that determines long-term reliability degradation

**Related Documents:**
- [Vehicle Inspection](VEHICLE_INSPECTION.md) - Reliability system, inspection reports, in-game effects
- [Economics](ECONOMICS.md) - Buy/sell pricing model, vanilla comparison
- [COMPATIBILITY.md](../COMPATIBILITY.md) - RVB mod integration details

---

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Core Concept | ✅ COMPLETE | Documented in this file |
| Data Model | ✅ COMPLETE | Added to UsedPlusMaintenance.lua |
| XML Schema | ✅ COMPLETE | workhorseLemonScale, maxReliabilityCeiling, component durabilities |
| Generation Logic | ✅ COMPLETE | generateNewVehicleScale(), generateUsedVehicleScale() |
| Repair Integration | ✅ COMPLETE | onVehicleRepaired() with ceiling degradation |
| Multiplayer Sync | ✅ COMPLETE | stream read/write added |
| Inspector Quote System | ✅ COMPLETE | 50 quotes across 10 tiers |
| Quote Selection Logic | ✅ COMPLETE | getInspectorQuote() function |
| Inspection Dialog UI | ⏳ PENDING | Need to add "Mechanic's Assessment" section to dialog |
| Quote Translations | ⏳ PENDING | Need 50 keys × 10 languages = 500 entries |
| **RVB Initial DNA Multiplier** | ✅ COMPLETE | v2.2.0: applyDNAToRVBLifetimes() |
| **RVB Repair Degradation** | ✅ COMPLETE | v2.2.0: applyRVBRepairDegradation() |
| **RVB Breakdown Degradation** | ✅ COMPLETE | v2.2.0: applyRVBBreakdownDegradation() |
| **UsedPlus Component Durability** | ✅ COMPLETE | v2.2.0: maxEngineDurability, etc. |
| **Fault Monitoring** | ✅ COMPLETE | v2.2.0: RVBWorkshopIntegration fault tracking |

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Core Mechanics](#core-mechanics)
3. [Mathematical Model](#mathematical-model)
4. [Vehicle Lifecycle Examples](#vehicle-lifecycle-examples)
5. [Inspector Quote System](#inspector-quote-system)
6. [Implementation Plan](#implementation-plan)
7. [Configuration Options](#configuration-options)
8. [Edge Cases & Balance](#edge-cases--balance)
9. [**RVB Progressive Degradation (v2.2.0)**](#rvb-progressive-degradation-v220)

---

## Design Philosophy

### The Problem with Fixed Reliability Caps

**Current System (v1.3.x):**
- All vehicles have a fixed `maxReliabilityAfterRepair = 0.95`
- Every vehicle degrades identically
- No differentiation between a "lucky find" and a "lemon"
- Predictable, but boring

**Player Experience Gap:**
In real life, some vehicles are legendary workhorses that run for 50,000 hours with minimal issues. Others are "lemons" - constant problems from day one, money pits that never quite work right. This variance is MISSING from our current system.

### The Solution: Hidden Vehicle DNA

**Proposed System (v1.4.0):**
- Each vehicle has a hidden `workhorseLemonScale` (0.0 to 1.0)
- This determines how much the reliability CEILING degrades per repair
- Workhorses (1.0) = ceiling never drops, can always repair to ~95%
- Lemons (0.0) = ceiling drops 1% per repair, eventually unrepairable
- Most vehicles are in between

**Key Insight:** Players don't know which type they have until they've owned it for a while. This creates:
- Emergent storytelling ("Old Betsy has 30,000 hours and still runs!")
- Meaningful attachment to good vehicles
- Strategic decisions about when to sell lemons
- Another dimension to used vehicle gambling

---

## Core Mechanics

### New Data Fields

```lua
-- Added to UsedPlusMaintenance spec:

-- Hidden "DNA" of the vehicle (0.0 = lemon, 1.0 = workhorse)
-- NEVER changes after vehicle creation
spec.workhorseLemonScale = 0.5

-- Current maximum achievable reliability (degrades over time)
-- Starts at 1.0, reduced by repairs based on lemonScale
spec.maxReliabilityCeiling = 1.0
```

### How It Works

**On Each Repair:**

```lua
function UsedPlusMaintenance.onVehicleRepaired(vehicle, repairCost)
    local spec = vehicle.spec_usedPlusMaintenance

    -- 1. Calculate ceiling degradation based on lemon scale
    -- Lemon (0.0) = 1% degradation per repair
    -- Workhorse (1.0) = 0% degradation per repair
    local degradationRate = (1 - spec.workhorseLemonScale) * 0.01

    -- 2. Reduce the ceiling
    spec.maxReliabilityCeiling = spec.maxReliabilityCeiling - degradationRate

    -- 3. Ensure minimum ceiling (vehicle is never completely unrepairable)
    spec.maxReliabilityCeiling = math.max(0.30, spec.maxReliabilityCeiling)

    -- 4. Apply repair bonus, capped by NEW ceiling
    local repairBonus = 0.15
    local newReliability = spec.engineReliability + repairBonus
    spec.engineReliability = math.min(spec.maxReliabilityCeiling, newReliability)
    -- (repeat for hydraulic and electrical)
end
```

### Scale Distribution

**For NEW vehicles (purchased from dealership):**
```lua
-- Slight bias toward quality (dealerships don't sell obvious lemons)
-- Bell curve centered at 0.6
workhorseLemonScale = 0.3 + (math.random() * 0.5) + (math.random() * 0.2)
-- Range: 0.3 to 1.0, average ~0.6
```

**For USED vehicles (from used market):**

The DNA distribution is **correlated with quality tier** - players who search for higher quality vehicles are more likely to find workhorses, while bargain hunters face higher lemon risk:

```lua
-- DNA distribution varies by quality tier selected
QUALITY_DNA_RANGES = {
    Poor      = { min = 0.00, max = 0.70, avg = 0.30 },  -- High lemon risk
    Any       = { min = 0.00, max = 0.85, avg = 0.40 },  -- Wide variance
    Fair      = { min = 0.15, max = 0.85, avg = 0.50 },  -- Balanced
    Good      = { min = 0.30, max = 0.95, avg = 0.60 },  -- Quality bias
    Excellent = { min = 0.50, max = 1.00, avg = 0.75 },  -- Workhorse bias
}

function generateUsedVehicleScale(qualityTier)
    local range = QUALITY_DNA_RANGES[qualityTier]
    -- Bell curve within tier's range
    local r1, r2 = math.random(), math.random()
    local scale = range.min + ((r1 + r2) / 2) * (range.max - range.min)
    return math.min(1.0, math.max(0.0, scale))
end
```

**Rationale:** Sellers know when they have a lemon and price accordingly. A vehicle priced at "Poor" quality is more likely to have hidden issues. Conversely, premium-priced "Excellent" vehicles have been vetted and are less likely to be lemons.

| Quality Tier | DNA Range | Avg DNA | Lemon Chance (< 0.30) | Workhorse Chance (> 0.80) |
|--------------|-----------|---------|----------------------|--------------------------|
| Poor | 0.00-0.70 | ~0.30 | ~45% | ~0% |
| Any | 0.00-0.85 | ~0.40 | ~35% | ~5% |
| Fair | 0.15-0.85 | ~0.50 | ~20% | ~10% |
| Good | 0.30-0.95 | ~0.60 | ~5% | ~20% |
| Excellent | 0.50-1.00 | ~0.75 | ~0% | ~40% |

**Key Insight:** Buying "Poor" quality is gambling - you might find a hidden gem (workhorse at 0.65) or a money pit (lemon at 0.10). Buying "Excellent" dramatically reduces lemon risk but costs more upfront.

---

## Mathematical Model

### Ceiling Degradation Formula

```
ceilingDegradation = (1 - workhorseLemonScale) × 0.01 × repairCount

Where:
- workhorseLemonScale: 0.0 (lemon) to 1.0 (workhorse)
- 0.01: Maximum degradation per repair (1%)
- repairCount: Number of times vehicle has been repaired
```

### Degradation Rate by Scale

| Scale Value | Type | Degradation/Repair | After 10 Repairs | After 50 Repairs |
|-------------|------|-------------------|------------------|------------------|
| 0.00 | Pure Lemon | 1.00% | 90% ceiling | 50% ceiling |
| 0.25 | Poor Quality | 0.75% | 92.5% ceiling | 62.5% ceiling |
| 0.50 | Average | 0.50% | 95% ceiling | 75% ceiling |
| 0.75 | Good Quality | 0.25% | 97.5% ceiling | 87.5% ceiling |
| 1.00 | Pure Workhorse | 0.00% | 100% ceiling | 100% ceiling |

### Minimum Ceiling

The ceiling can never drop below **30%**. This ensures:
- Vehicles are never completely unrepairable
- Even worst lemons can limp along at reduced capacity
- Creates a "floor" for vehicle functionality

---

## Vehicle Lifecycle Examples

### Example 1: The Workhorse (Scale = 0.95)

**Purchase:** Player buys a used John Deere 6R, scale = 0.95 (lucky find!)

| Event | Ceiling | Engine Rel. | Notes |
|-------|---------|-------------|-------|
| Purchase | 100% | 45% | Used, needs work |
| Repair #1 | 99.95% | 60% | Almost no degradation |
| Repair #5 | 99.75% | 95% | Near-max reliability |
| Repair #20 | 99.0% | 95% | Still excellent |
| Repair #100 | 95.0% | 95% | Decades of service! |

**Player Experience:** "This tractor is incredible. 50,000 hours and still runs like a dream!"

### Example 2: The Lemon (Scale = 0.10)

**Purchase:** Player buys a used Fendt, scale = 0.10 (uh oh...)

| Event | Ceiling | Engine Rel. | Notes |
|-------|---------|-------------|-------|
| Purchase | 100% | 50% | Seems okay initially |
| Repair #1 | 99.1% | 65% | Normal repair |
| Repair #5 | 95.5% | 80% | Still okay... |
| Repair #10 | 91.0% | 91% | Ceiling approaching reliability |
| Repair #15 | 86.5% | 86.5% | CAN'T REPAIR HIGHER |
| Repair #20 | 82.0% | 82% | Getting worse! |
| Repair #50 | 55.0% | 55% | Major reliability issues |
| Repair #78 | 30.0% | 30% | At minimum ceiling |

**Player Experience:** "Why does this thing keep breaking?! I've repaired it 20 times and it's getting WORSE!"

### Example 3: Average Vehicle (Scale = 0.50)

**Purchase:** Player buys new from dealership, scale = 0.50 (average)

| Event | Ceiling | Engine Rel. | Notes |
|-------|---------|-------------|-------|
| New Purchase | 100% | 100% | Brand new! |
| Use (no repair) | 100% | 85% | Normal wear |
| Repair #1 | 99.5% | 99.5% | Back to near-max |
| Use + Repair #5 | 97.5% | 97.5% | Slight ceiling drop |
| Repair #20 | 90.0% | 90% | Noticeable limit |
| Repair #50 | 75.0% | 75% | Significant degradation |

**Player Experience:** "Solid tractor, but after 10 years it's not what it used to be. Time to upgrade."

---

## Inspector Quote System

### Design Intent

Rather than showing a numeric "Build Quality: 73%" value, the inspection report includes a **quote from the mechanic** that hints at the vehicle's workhorse/lemon nature. This:

1. **Preserves mystery** - Player doesn't see exact numbers
2. **Adds personality** - Feels like talking to a real mechanic
3. **Provides breadcrumbs** - Observant players can learn the patterns
4. **Enhances immersion** - More engaging than raw statistics

### Quote Selection Logic

```lua
--[[
    Get inspector quote based on workhorse/lemon scale
    Returns a random quote from the appropriate tier
]]
function UsedPlusMaintenance.getInspectorQuote(workhorseLemonScale)
    local quotes = UsedPlusMaintenance.INSPECTOR_QUOTES

    -- Determine tier based on scale
    local tier
    if workhorseLemonScale < 0.10 then
        tier = "catastrophic"  -- 0.00 - 0.09
    elseif workhorseLemonScale < 0.20 then
        tier = "terrible"      -- 0.10 - 0.19
    elseif workhorseLemonScale < 0.30 then
        tier = "poor"          -- 0.20 - 0.29
    elseif workhorseLemonScale < 0.40 then
        tier = "belowAverage"  -- 0.30 - 0.39
    elseif workhorseLemonScale < 0.50 then
        tier = "slightlyBelow" -- 0.40 - 0.49
    elseif workhorseLemonScale < 0.60 then
        tier = "average"       -- 0.50 - 0.59
    elseif workhorseLemonScale < 0.70 then
        tier = "aboveAverage"  -- 0.60 - 0.69
    elseif workhorseLemonScale < 0.80 then
        tier = "good"          -- 0.70 - 0.79
    elseif workhorseLemonScale < 0.90 then
        tier = "excellent"     -- 0.80 - 0.89
    else
        tier = "legendary"     -- 0.90 - 1.00
    end

    -- Return random quote from tier
    local tierQuotes = quotes[tier]
    return tierQuotes[math.random(#tierQuotes)]
end
```

### Complete Quote Library

#### Tier: CATASTROPHIC (0.00 - 0.09) - Pure Lemons

| # | i18n Key | English Quote |
|---|----------|---------------|
| 1 | `usedplus_quote_cat_1` | "I'm genuinely surprised this made it to the lot." |
| 2 | `usedplus_quote_cat_2` | "Whoever assembled this should find a new career." |
| 3 | `usedplus_quote_cat_3` | "I'd tell ya to run, but I reckon this thing couldn't catch ya anyway." |
| 4 | `usedplus_quote_cat_4` | "I'd burn some sage before driving this one off the lot." |
| 5 | `usedplus_quote_cat_5` | "This thing's got more bad juju than a broken mirror factory." |

#### Tier: TERRIBLE (0.10 - 0.19) - Severe Issues

| # | i18n Key | English Quote |
|---|----------|---------------|
| 6 | `usedplus_quote_ter_1` | "My cousin had one like this. Used it for a chicken coop after. That's about all it was good for." |
| 7 | `usedplus_quote_ter_2` | "Some machines just come off the line wrong. This is one of them." |
| 8 | `usedplus_quote_ter_3` | "My advice? Budget for a lot of shop visits." |
| 9 | `usedplus_quote_ter_4` | "If machines could be cursed, this one surely is." |
| 10 | `usedplus_quote_ter_5` | "Something ain't right with this one. Can't explain it, but I feel it in my bones." |

#### Tier: POOR (0.20 - 0.29) - Problematic

| # | i18n Key | English Quote |
|---|----------|---------------|
| 11 | `usedplus_quote_poor_1` | "She'll run, but don't expect her to thank you for it." |
| 12 | `usedplus_quote_poor_2` | "This here's what we call a 'parts tractor' back home." |
| 13 | `usedplus_quote_poor_3` | "Might want to keep your mechanic on speed dial." |
| 14 | `usedplus_quote_poor_4` | "My grandfather would've called this one 'snake-bit.'" |
| 15 | `usedplus_quote_poor_5` | "Some tractors attract trouble like a lightning rod. This is one of 'em." |

#### Tier: BELOW AVERAGE (0.30 - 0.39) - Mediocre Build

| # | i18n Key | English Quote |
|---|----------|---------------|
| 16 | `usedplus_quote_below_1` | "Nothing special here. Just... adequate." |
| 17 | `usedplus_quote_below_2` | "She's about as reliable as a screen door on a submarine." |
| 18 | `usedplus_quote_below_3` | "She'll get the job done. Eventually." |
| 19 | `usedplus_quote_below_4` | "Not saying it's haunted, but I wouldn't leave it running alone at night." |
| 20 | `usedplus_quote_below_5` | "Some machines carry a little bad karma. This one's got a touch." |

#### Tier: SLIGHTLY BELOW (0.40 - 0.49) - Minor Concerns

| # | i18n Key | English Quote |
|---|----------|---------------|
| 21 | `usedplus_quote_slight_1` | "Acceptable tolerances. Barely." |
| 22 | `usedplus_quote_slight_2` | "I've seen better put together by my nephew with a wrench and some baling wire." |
| 23 | `usedplus_quote_slight_3` | "Standard factory quality. That's all I can say." |
| 24 | `usedplus_quote_slight_4` | "My gut says she'll give you a few headaches. Gut's usually right." |
| 25 | `usedplus_quote_slight_5` | "There's an old saying - some iron just don't want to cooperate." |

#### Tier: AVERAGE (0.50 - 0.59) - Middle of the Road

| # | i18n Key | English Quote |
|---|----------|---------------|
| 26 | `usedplus_quote_avg_1` | "Right down the middle. Nothing remarkable, nothing concerning." |
| 27 | `usedplus_quote_avg_2` | "She'll give you fair service for fair treatment." |
| 28 | `usedplus_quote_avg_3` | "It ain't fancy, but it'll plow a field same as any other." |
| 29 | `usedplus_quote_avg_4` | "The spirits are neutral on this one, if you believe in that sort of thing." |
| 30 | `usedplus_quote_avg_5` | "Not blessed, not cursed. Just... a machine." |

#### Tier: ABOVE AVERAGE (0.60 - 0.69) - Decent Quality

| # | i18n Key | English Quote |
|---|----------|---------------|
| 31 | `usedplus_quote_above_1` | "Whoever put this together knew what they were doing." |
| 32 | `usedplus_quote_above_2` | "That's a machine that'll be with you through more than a few harvests." |
| 33 | `usedplus_quote_above_3` | "Good bones on this one." |
| 34 | `usedplus_quote_above_4` | "Got a good feeling about this one. Call it mechanic's intuition." |
| 35 | `usedplus_quote_above_5` | "Some machines just want to work. This one's got that spirit in her." |

#### Tier: GOOD (0.70 - 0.79) - Quality Build

| # | i18n Key | English Quote |
|---|----------|---------------|
| 36 | `usedplus_quote_good_1` | "This one came out of the factory right." |
| 37 | `usedplus_quote_good_2` | "Now that's the kind of iron my grandpappy would've been proud to park in the barn." |
| 38 | `usedplus_quote_good_3` | "Someone on the assembly line was having a good day." |
| 39 | `usedplus_quote_good_4` | "My old mentor used to say some tractors are born lucky. This might be one." |
| 40 | `usedplus_quote_good_5` | "There's good iron and bad iron. This here's the good stuff." |

#### Tier: EXCELLENT (0.80 - 0.89) - Exceptional Build

| # | i18n Key | English Quote |
|---|----------|---------------|
| 41 | `usedplus_quote_exc_1` | "Now THIS is how they should all be built." |
| 42 | `usedplus_quote_exc_2` | "She's a keeper if I ever saw one." |
| 43 | `usedplus_quote_exc_3` | "Finer than frog hair split four ways - and that's sayin' somethin'." |
| 44 | `usedplus_quote_exc_4` | "If I believed in lucky stars, I'd say this one was born under a whole constellation." |
| 45 | `usedplus_quote_exc_5` | "Some machines got a soul. This one's got a good one." |

#### Tier: LEGENDARY (0.90 - 1.00) - Workhorse

| # | i18n Key | English Quote |
|---|----------|---------------|
| 46 | `usedplus_quote_leg_1` | "In 30 years, I've seen maybe a dozen this well built." |
| 47 | `usedplus_quote_leg_2` | "This one here's got more soul than a Sunday gospel choir." |
| 48 | `usedplus_quote_leg_3` | "Hold onto this one. You won't find another like it." |
| 49 | `usedplus_quote_leg_4` | "Old-timers used to talk about tractors like this. Thought they were just legends." |
| 50 | `usedplus_quote_leg_5` | "This one's got guardian angels working overtime in the engine bay." |

### Quote Summary Table

| Tier | Scale Range | # Quotes | Sentiment | Example Quote |
|------|-------------|----------|-----------|---------------|
| Catastrophic | 0.00-0.09 | 5 | Run away | "Couldn't catch ya anyway...", "Burn some sage..." |
| Terrible | 0.10-0.19 | 5 | Major warning | "Used it for a chicken coop...", "If machines could be cursed..." |
| Poor | 0.20-0.29 | 5 | Concerning | "Parts tractor back home...", "Snake-bit..." |
| Below Average | 0.30-0.39 | 5 | Meh | "Screen door on a submarine...", "Bad karma..." |
| Slightly Below | 0.40-0.49 | 5 | Tepid | "Wrench and baling wire...", "Iron don't cooperate..." |
| Average | 0.50-0.59 | 5 | Neutral | "Plow a field same as any other...", "Not blessed, not cursed..." |
| Above Average | 0.60-0.69 | 5 | Positive | "More than a few harvests...", "Got that spirit..." |
| Good | 0.70-0.79 | 5 | Encouraging | "Grandpappy would be proud...", "Good iron..." |
| Excellent | 0.80-0.89 | 5 | Enthusiastic | "Finer than frog hair...", "Got a soul..." |
| Legendary | 0.90-1.00 | 5 | Rare praise | "Sunday gospel choir...", "Guardian angels..." |

**Total: 50 quotes** (5 per tier: 2 technical, 2 superstitious, 1 country)

### UI Integration

The quote appears in the **Inspection Report Dialog** in a dedicated section:

```
┌─────────────────────────────────────────────────────────────┐
│  INSPECTION REPORT                                          │
├─────────────────────────────────────────────────────────────┤
│  Vehicle: John Deere 6R 150                                 │
│  Hours: 2,450  |  Age: 4 years  |  Damage: 35%              │
├─────────────────────────────────────────────────────────────┤
│  COMPONENT RATINGS                                          │
│  Engine:      62%  [Good]                                   │
│  Hydraulic:   45%  [Fair]                                   │
│  Electrical:  71%  [Good]                                   │
├─────────────────────────────────────────────────────────────┤
│  MECHANIC'S ASSESSMENT                                      │
│                                                             │
│  "Whoever put this together knew what they were doing.      │
│   Nice tight tolerances. Should treat you well."            │
│                                                     - Jim   │
├─────────────────────────────────────────────────────────────┤
│  Overall: 59%  |  Est. Repair: $4,200                       │
│  [BUY]  [GO BACK]  [DECLINE]                                │
└─────────────────────────────────────────────────────────────┘
```

### Lua Data Structure

```lua
UsedPlusMaintenance.INSPECTOR_QUOTES = {
    catastrophic = {
        "usedplus_quote_cat_1",
        "usedplus_quote_cat_2",
        "usedplus_quote_cat_3",
        "usedplus_quote_cat_4",  -- Superstitious
        "usedplus_quote_cat_5",  -- Superstitious
    },
    terrible = {
        "usedplus_quote_ter_1",
        "usedplus_quote_ter_2",
        "usedplus_quote_ter_3",
        "usedplus_quote_ter_4",  -- Superstitious
        "usedplus_quote_ter_5",  -- Superstitious
    },
    poor = {
        "usedplus_quote_poor_1",
        "usedplus_quote_poor_2",
        "usedplus_quote_poor_3",
        "usedplus_quote_poor_4",  -- Superstitious
        "usedplus_quote_poor_5",  -- Superstitious
    },
    belowAverage = {
        "usedplus_quote_below_1",
        "usedplus_quote_below_2",
        "usedplus_quote_below_3",
        "usedplus_quote_below_4",  -- Superstitious
        "usedplus_quote_below_5",  -- Superstitious
    },
    slightlyBelow = {
        "usedplus_quote_slight_1",
        "usedplus_quote_slight_2",
        "usedplus_quote_slight_3",
        "usedplus_quote_slight_4",  -- Superstitious
        "usedplus_quote_slight_5",  -- Superstitious
    },
    average = {
        "usedplus_quote_avg_1",
        "usedplus_quote_avg_2",
        "usedplus_quote_avg_3",
        "usedplus_quote_avg_4",  -- Superstitious
        "usedplus_quote_avg_5",  -- Superstitious
    },
    aboveAverage = {
        "usedplus_quote_above_1",
        "usedplus_quote_above_2",
        "usedplus_quote_above_3",
        "usedplus_quote_above_4",  -- Superstitious
        "usedplus_quote_above_5",  -- Superstitious
    },
    good = {
        "usedplus_quote_good_1",
        "usedplus_quote_good_2",
        "usedplus_quote_good_3",
        "usedplus_quote_good_4",  -- Superstitious
        "usedplus_quote_good_5",  -- Superstitious
    },
    excellent = {
        "usedplus_quote_exc_1",
        "usedplus_quote_exc_2",
        "usedplus_quote_exc_3",
        "usedplus_quote_exc_4",  -- Superstitious
        "usedplus_quote_exc_5",  -- Superstitious
    },
    legendary = {
        "usedplus_quote_leg_1",
        "usedplus_quote_leg_2",
        "usedplus_quote_leg_3",
        "usedplus_quote_leg_4",  -- Superstitious
        "usedplus_quote_leg_5",  -- Superstitious
    },
}
```

### Translation Keys (All 10 Languages Required)

When implementing, add all 50 quote keys to `translation_en.xml`, then translate to all other 9 languages.

**English keys (translation_en.xml):**

```xml
<!-- CATASTROPHIC (0.00-0.09) - 5 quotes -->
<text name="usedplus_quote_cat_1" text="I'm genuinely surprised this made it to the lot."/>
<text name="usedplus_quote_cat_2" text="Whoever assembled this should find a new career."/>
<text name="usedplus_quote_cat_3" text="I'd tell ya to run, but I reckon this thing couldn't catch ya anyway."/>
<text name="usedplus_quote_cat_4" text="I'd burn some sage before driving this one off the lot."/>
<text name="usedplus_quote_cat_5" text="This thing's got more bad juju than a broken mirror factory."/>

<!-- TERRIBLE (0.10-0.19) - 5 quotes -->
<text name="usedplus_quote_ter_1" text="My cousin had one like this. Used it for a chicken coop after. That's about all it was good for."/>
<text name="usedplus_quote_ter_2" text="Some machines just come off the line wrong. This is one of them."/>
<text name="usedplus_quote_ter_3" text="My advice? Budget for a lot of shop visits."/>
<text name="usedplus_quote_ter_4" text="If machines could be cursed, this one surely is."/>
<text name="usedplus_quote_ter_5" text="Something ain't right with this one. Can't explain it, but I feel it in my bones."/>

<!-- POOR (0.20-0.29) - 5 quotes -->
<text name="usedplus_quote_poor_1" text="She'll run, but don't expect her to thank you for it."/>
<text name="usedplus_quote_poor_2" text="This here's what we call a 'parts tractor' back home."/>
<text name="usedplus_quote_poor_3" text="Might want to keep your mechanic on speed dial."/>
<text name="usedplus_quote_poor_4" text="My grandfather would've called this one 'snake-bit.'"/>
<text name="usedplus_quote_poor_5" text="Some tractors attract trouble like a lightning rod. This is one of 'em."/>

<!-- BELOW AVERAGE (0.30-0.39) - 5 quotes -->
<text name="usedplus_quote_below_1" text="Nothing special here. Just... adequate."/>
<text name="usedplus_quote_below_2" text="She's about as reliable as a screen door on a submarine."/>
<text name="usedplus_quote_below_3" text="She'll get the job done. Eventually."/>
<text name="usedplus_quote_below_4" text="Not saying it's haunted, but I wouldn't leave it running alone at night."/>
<text name="usedplus_quote_below_5" text="Some machines carry a little bad karma. This one's got a touch."/>

<!-- SLIGHTLY BELOW (0.40-0.49) - 5 quotes -->
<text name="usedplus_quote_slight_1" text="Acceptable tolerances. Barely."/>
<text name="usedplus_quote_slight_2" text="I've seen better put together by my nephew with a wrench and some baling wire."/>
<text name="usedplus_quote_slight_3" text="Standard factory quality. That's all I can say."/>
<text name="usedplus_quote_slight_4" text="My gut says she'll give you a few headaches. Gut's usually right."/>
<text name="usedplus_quote_slight_5" text="There's an old saying - some iron just don't want to cooperate."/>

<!-- AVERAGE (0.50-0.59) - 5 quotes -->
<text name="usedplus_quote_avg_1" text="Right down the middle. Nothing remarkable, nothing concerning."/>
<text name="usedplus_quote_avg_2" text="She'll give you fair service for fair treatment."/>
<text name="usedplus_quote_avg_3" text="It ain't fancy, but it'll plow a field same as any other."/>
<text name="usedplus_quote_avg_4" text="The spirits are neutral on this one, if you believe in that sort of thing."/>
<text name="usedplus_quote_avg_5" text="Not blessed, not cursed. Just... a machine."/>

<!-- ABOVE AVERAGE (0.60-0.69) - 5 quotes -->
<text name="usedplus_quote_above_1" text="Whoever put this together knew what they were doing."/>
<text name="usedplus_quote_above_2" text="That's a machine that'll be with you through more than a few harvests."/>
<text name="usedplus_quote_above_3" text="Good bones on this one."/>
<text name="usedplus_quote_above_4" text="Got a good feeling about this one. Call it mechanic's intuition."/>
<text name="usedplus_quote_above_5" text="Some machines just want to work. This one's got that spirit in her."/>

<!-- GOOD (0.70-0.79) - 5 quotes -->
<text name="usedplus_quote_good_1" text="This one came out of the factory right."/>
<text name="usedplus_quote_good_2" text="Now that's the kind of iron my grandpappy would've been proud to park in the barn."/>
<text name="usedplus_quote_good_3" text="Someone on the assembly line was having a good day."/>
<text name="usedplus_quote_good_4" text="My old mentor used to say some tractors are born lucky. This might be one."/>
<text name="usedplus_quote_good_5" text="There's good iron and bad iron. This here's the good stuff."/>

<!-- EXCELLENT (0.80-0.89) - 5 quotes -->
<text name="usedplus_quote_exc_1" text="Now THIS is how they should all be built."/>
<text name="usedplus_quote_exc_2" text="She's a keeper if I ever saw one."/>
<text name="usedplus_quote_exc_3" text="Finer than frog hair split four ways - and that's sayin' somethin'."/>
<text name="usedplus_quote_exc_4" text="If I believed in lucky stars, I'd say this one was born under a whole constellation."/>
<text name="usedplus_quote_exc_5" text="Some machines got a soul. This one's got a good one."/>

<!-- LEGENDARY (0.90-1.00) - 5 quotes -->
<text name="usedplus_quote_leg_1" text="In 30 years, I've seen maybe a dozen this well built."/>
<text name="usedplus_quote_leg_2" text="This one here's got more soul than a Sunday gospel choir."/>
<text name="usedplus_quote_leg_3" text="Hold onto this one. You won't find another like it."/>
<text name="usedplus_quote_leg_4" text="Old-timers used to talk about tractors like this. Thought they were just legends."/>
<text name="usedplus_quote_leg_5" text="This one's got guardian angels working overtime in the engine bay."/>
```

**Note:** These 50 keys must be translated to all 10 supported languages:
- DE (German), FR (French), ES (Spanish), IT (Italian)
- PL (Polish), RU (Russian), CZ (Czech), BR (Brazilian Portuguese), UK (Ukrainian)

---

## Implementation Plan

### Phase 1: Data Model (Required Files)

**File: `UsedPlusMaintenance.lua`**

#### 1.1 Add Schema Registration
```lua
-- In initSpecialization(), add:
schemaSavegame:register(XMLValueType.FLOAT, key .. ".workhorseLemonScale",
    "Hidden quality score (0=lemon, 1=workhorse)", 0.5)
schemaSavegame:register(XMLValueType.FLOAT, key .. ".maxReliabilityCeiling",
    "Current max achievable reliability", 1.0)
```

#### 1.2 Add Default Values in onLoad()
```lua
-- In onLoad(), add:
-- Workhorse/Lemon Scale (hidden vehicle DNA)
spec.workhorseLemonScale = 0.5  -- Will be set properly on purchase
spec.maxReliabilityCeiling = 1.0  -- Starts at 100%, degrades over repairs
```

#### 1.3 Add Load/Save
```lua
-- In onPostLoad(), add:
spec.workhorseLemonScale = xmlFile:getValue(key .. ".workhorseLemonScale", 0.5)
spec.maxReliabilityCeiling = xmlFile:getValue(key .. ".maxReliabilityCeiling", 1.0)

-- In saveToXMLFile(), add:
xmlFile:setValue(key .. ".workhorseLemonScale", spec.workhorseLemonScale)
xmlFile:setValue(key .. ".maxReliabilityCeiling", spec.maxReliabilityCeiling)
```

#### 1.4 Add Multiplayer Sync
```lua
-- In onReadStream(), add:
spec.workhorseLemonScale = streamReadFloat32(streamId)
spec.maxReliabilityCeiling = streamReadFloat32(streamId)

-- In onWriteStream(), add:
streamWriteFloat32(streamId, spec.workhorseLemonScale)
streamWriteFloat32(streamId, spec.maxReliabilityCeiling)
```

### Phase 2: Repair Integration

#### 2.1 Modify onVehicleRepaired()
```lua
function UsedPlusMaintenance.onVehicleRepaired(vehicle, repairCost)
    local spec = vehicle.spec_usedPlusMaintenance
    if spec == nil then return end

    -- Update maintenance history
    spec.repairCount = spec.repairCount + 1
    spec.totalRepairCost = spec.totalRepairCost + repairCost
    spec.lastRepairDate = g_currentMission.environment.dayTime or 0

    -- PHASE 1.4: Calculate ceiling degradation based on lemon scale
    local degradationRate = (1 - spec.workhorseLemonScale) *
        UsedPlusMaintenance.CONFIG.ceilingDegradationMax
    spec.maxReliabilityCeiling = math.max(
        UsedPlusMaintenance.CONFIG.minReliabilityCeiling,
        spec.maxReliabilityCeiling - degradationRate
    )

    -- Apply repair bonus, capped by CURRENT ceiling (not fixed 95%)
    local repairBonus = UsedPlusMaintenance.CONFIG.reliabilityRepairBonus
    local ceiling = spec.maxReliabilityCeiling

    spec.engineReliability = math.min(ceiling, spec.engineReliability + repairBonus)
    spec.hydraulicReliability = math.min(ceiling, spec.hydraulicReliability + repairBonus)
    spec.electricalReliability = math.min(ceiling, spec.electricalReliability + repairBonus)

    UsedPlus.logDebug(string.format(
        "Vehicle repaired: %s - ceiling=%.1f%%, engine=%.2f, hydraulic=%.2f, electrical=%.2f",
        vehicle:getName(), spec.maxReliabilityCeiling * 100,
        spec.engineReliability, spec.hydraulicReliability, spec.electricalReliability))
end
```

### Phase 3: Generation Logic

#### 3.1 Add Generation Functions
```lua
--[[
    Generate workhorse/lemon scale for a new vehicle
    New vehicles from dealership have slight quality bias
]]
function UsedPlusMaintenance.generateNewVehicleScale()
    -- Bell curve centered at 0.6, range 0.3-1.0
    -- Dealerships don't sell obvious lemons
    local r1 = math.random()
    local r2 = math.random()
    local scale = 0.3 + (r1 * 0.5) + (r2 * 0.2)
    return math.min(1.0, math.max(0.0, scale))
end

--[[
    Generate workhorse/lemon scale for a used vehicle listing
    Used market has full range - could be gem or lemon
]]
function UsedPlusMaintenance.generateUsedVehicleScale()
    -- Flat-ish distribution with center bias, range 0.0-1.0
    local r1 = math.random()
    local r2 = math.random()
    local r3 = math.random()
    local scale = (r1 * 0.4) + (r2 * 0.4) + (r3 * 0.2)
    return math.min(1.0, math.max(0.0, scale))
end

--[[
    Calculate initial ceiling for used vehicle based on previous ownership
    Simulates unknown repair history
    @param estimatedPreviousRepairs - Estimated from age/hours
]]
function UsedPlusMaintenance.calculateInitialCeiling(workhorseLemonScale, estimatedPreviousRepairs)
    local degradationRate = (1 - workhorseLemonScale) *
        UsedPlusMaintenance.CONFIG.ceilingDegradationMax
    local totalDegradation = degradationRate * estimatedPreviousRepairs
    local ceiling = 1.0 - totalDegradation
    return math.max(UsedPlusMaintenance.CONFIG.minReliabilityCeiling, ceiling)
end
```

#### 3.2 Update generateReliabilityScores()
```lua
function UsedPlusMaintenance.generateReliabilityScores(damage, age, hours)
    -- Generate base reliability scores (existing code)
    local reliabilityBase = 1 - (damage or 0)
    local engineReliability = reliabilityBase + randomVariance(0.2)
    local hydraulicReliability = reliabilityBase + randomVariance(0.25)
    local electricalReliability = reliabilityBase + randomVariance(0.15)

    -- Clamp
    engineReliability = math.max(0.1, math.min(1.0, engineReliability))
    hydraulicReliability = math.max(0.1, math.min(1.0, hydraulicReliability))
    electricalReliability = math.max(0.1, math.min(1.0, electricalReliability))

    -- NEW: Generate workhorse/lemon scale
    local workhorseLemonScale = UsedPlusMaintenance.generateUsedVehicleScale()

    -- NEW: Estimate previous repairs from age/hours and calculate ceiling
    local estimatedRepairs = math.floor((hours or 0) / 500)  -- ~1 repair per 500 hours
    estimatedRepairs = estimatedRepairs + (age or 0)  -- Plus 1 per year
    local maxReliabilityCeiling = UsedPlusMaintenance.calculateInitialCeiling(
        workhorseLemonScale, estimatedRepairs)

    -- Cap reliability scores by ceiling
    engineReliability = math.min(engineReliability, maxReliabilityCeiling)
    hydraulicReliability = math.min(hydraulicReliability, maxReliabilityCeiling)
    electricalReliability = math.min(electricalReliability, maxReliabilityCeiling)

    return {
        engineReliability = engineReliability,
        hydraulicReliability = hydraulicReliability,
        electricalReliability = electricalReliability,
        workhorseLemonScale = workhorseLemonScale,
        maxReliabilityCeiling = maxReliabilityCeiling,
        wasInspected = false
    }
end
```

### Phase 4: Config Options

```lua
-- Add to CONFIG table:
UsedPlusMaintenance.CONFIG = {
    -- ... existing options ...

    -- Workhorse/Lemon Scale settings
    ceilingDegradationMax = 0.01,     -- Max 1% ceiling loss per repair (for lemons)
    minReliabilityCeiling = 0.30,     -- Ceiling can never go below 30%
    enableLemonScale = true,          -- Feature toggle
}
```

### Phase 5: Inspector Quote System

#### 5.1 Add Quote Data Structure

Add to `UsedPlusMaintenance.lua` after CONFIG:

```lua
UsedPlusMaintenance.INSPECTOR_QUOTES = {
    catastrophic = {
        "usedplus_quote_cat_1",
        "usedplus_quote_cat_2",
        "usedplus_quote_cat_3",
    },
    terrible = {
        "usedplus_quote_ter_1",
        "usedplus_quote_ter_2",
        "usedplus_quote_ter_3",
    },
    poor = {
        "usedplus_quote_poor_1",
        "usedplus_quote_poor_2",
        "usedplus_quote_poor_3",
    },
    belowAverage = {
        "usedplus_quote_below_1",
        "usedplus_quote_below_2",
        "usedplus_quote_below_3",
    },
    slightlyBelow = {
        "usedplus_quote_slight_1",
        "usedplus_quote_slight_2",
        "usedplus_quote_slight_3",
    },
    average = {
        "usedplus_quote_avg_1",
        "usedplus_quote_avg_2",
        "usedplus_quote_avg_3",
    },
    aboveAverage = {
        "usedplus_quote_above_1",
        "usedplus_quote_above_2",
        "usedplus_quote_above_3",
    },
    good = {
        "usedplus_quote_good_1",
        "usedplus_quote_good_2",
        "usedplus_quote_good_3",
    },
    excellent = {
        "usedplus_quote_exc_1",
        "usedplus_quote_exc_2",
        "usedplus_quote_exc_3",
    },
    legendary = {
        "usedplus_quote_leg_1",
        "usedplus_quote_leg_2",
        "usedplus_quote_leg_3",
    },
}
```

#### 5.2 Add Quote Selection Function

```lua
--[[
    Get inspector quote based on workhorse/lemon scale
    Returns localized quote text from the appropriate tier
    @param workhorseLemonScale - The vehicle's hidden quality score (0.0-1.0)
    @return string - Localized quote text
]]
function UsedPlusMaintenance.getInspectorQuote(workhorseLemonScale)
    local quotes = UsedPlusMaintenance.INSPECTOR_QUOTES

    -- Determine tier based on scale (10 tiers, 0.1 each)
    local tier
    if workhorseLemonScale < 0.10 then
        tier = "catastrophic"
    elseif workhorseLemonScale < 0.20 then
        tier = "terrible"
    elseif workhorseLemonScale < 0.30 then
        tier = "poor"
    elseif workhorseLemonScale < 0.40 then
        tier = "belowAverage"
    elseif workhorseLemonScale < 0.50 then
        tier = "slightlyBelow"
    elseif workhorseLemonScale < 0.60 then
        tier = "average"
    elseif workhorseLemonScale < 0.70 then
        tier = "aboveAverage"
    elseif workhorseLemonScale < 0.80 then
        tier = "good"
    elseif workhorseLemonScale < 0.90 then
        tier = "excellent"
    else
        tier = "legendary"
    end

    -- Select random quote from tier
    local tierQuotes = quotes[tier]
    local quoteKey = tierQuotes[math.random(#tierQuotes)]

    -- Return localized text
    return g_i18n:getText(quoteKey)
end
```

#### 5.3 Update InspectionReportDialog.lua

Add quote display in `updateDisplay()`:

```lua
-- Get inspector quote based on workhorse/lemon scale
local inspectorQuote = "Vehicle condition assessed."
if usedPlusData and usedPlusData.workhorseLemonScale then
    if UsedPlusMaintenance and UsedPlusMaintenance.getInspectorQuote then
        inspectorQuote = UsedPlusMaintenance.getInspectorQuote(usedPlusData.workhorseLemonScale)
    end
end

-- Display in UI
if self.mechanicQuoteText then
    self.mechanicQuoteText:setText('"' .. inspectorQuote .. '"')
end
```

#### 5.4 Update InspectionReportDialog.xml

Add mechanic quote section:

```xml
<!-- Mechanic's Assessment Section -->
<GuiElement profile="irMechanicSection" position="0px -340px">
    <Bitmap profile="irSectionBg" position="0px 0px"/>
    <Text profile="irSectionHeader" position="0px -5px" text="MECHANIC'S ASSESSMENT"/>
    <Text profile="irQuoteText" id="mechanicQuoteText" position="0px -35px"
          text='"About what you'd expect from the factory."'/>
    <Text profile="irQuoteAttrib" position="280px -65px" text="- Jim"/>
</GuiElement>
```

#### 5.5 Add Translations (30 keys × 10 languages)

See [Translation Keys](#translation-keys-all-10-languages-required) section for full list.

Files to update:
- `translations/translation_en.xml`
- `translations/translation_de.xml`
- `translations/translation_fr.xml`
- `translations/translation_es.xml`
- `translations/translation_it.xml`
- `translations/translation_pl.xml`
- `translations/translation_ru.xml`
- `translations/translation_cz.xml`
- `translations/translation_br.xml`
- `translations/translation_uk.xml`

---

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `enableLemonScale` | true | Enable/disable entire system |
| `ceilingDegradationMax` | 0.01 | Max ceiling loss per repair (1%) |
| `minReliabilityCeiling` | 0.30 | Minimum ceiling (30%) |

---

## Edge Cases & Balance

### Q: What about existing vehicles in saves?

**A:** Vehicles without `workhorseLemonScale` will default to 0.5 (average) and ceiling of 1.0. They'll start degrading normally from their next repair.

### Q: Should inspections reveal the scale?

**Solution: Inspector Quote System** (see [Inspector Quote System](#inspector-quote-system))

Rather than showing numbers, the mechanic gives a **colorful quote** that hints at the vehicle's quality:
- Lemon: "I'd keep my receipt handy if I were you..."
- Average: "About what you'd expect from the factory."
- Workhorse: "In 30 years, I've seen maybe a dozen this well built."

This preserves mystery while giving observant players useful information.

### Q: Can players game the system?

**Not really:**
- Scale is set at creation, never changes
- Only way to discover is through experience
- Can't inspect before buying (for used)
- Even inspection only gives vague indication

### Q: What about brand reputation?

**Future Enhancement:** Could bias scale generation by brand:
- Premium brands (Fendt, John Deere): Average scale 0.6-0.7
- Budget brands: Average scale 0.4-0.5
- This is NOT in initial implementation

---

## Phase 2 Enhancements: Damage/Wear Rate Modifiers

### Concept

Beyond ceiling degradation, the workhorseLemonScale could also affect how quickly vehicles accumulate damage and wear in normal operation:

| DNA Value | Reliability Ceiling | Damage Rate | Wear Rate | Net Effect |
|-----------|---------------------|-------------|-----------|------------|
| Lemon (0.0) | Degrades fastest | +30% faster | +30% faster | Money pit |
| Average (0.5) | Normal | Normal | Normal | Standard |
| Workhorse (1.0) | Never degrades | -20% slower | -20% slower | Low TCO |

### Technical Implementation

Override the `Wearable.updateWear()` and `Motorized.updateDamage()` functions:

```lua
-- Example: Override wear calculation
local originalUpdateWear = Wearable.updateWear
function Wearable:updateWear(dt)
    local spec = self.spec_usedPlusMaintenance
    if spec and spec.workhorseLemonScale then
        -- Workhorses (1.0) = 80% normal wear rate
        -- Lemons (0.0) = 130% normal wear rate
        local wearMultiplier = 1.3 - (spec.workhorseLemonScale * 0.5)
        dt = dt * wearMultiplier
    end
    originalUpdateWear(self, dt)
end
```

### Rationale

A poorly-aligned machine (lemon) experiences:
- More friction in moving parts
- Higher operating temperatures
- More stress on components
- Faster paint oxidation/wear

A well-built machine (workhorse) experiences:
- Smooth operation with minimal friction
- Optimal heat dissipation
- Lower component stress
- Better overall durability

### Why Phase 2?

This enhancement requires:
- Hooking into base game specializations
- Careful balance testing
- May conflict with other mods

**Recommendation:** Implement Phase 1 first (core DNA + ceiling degradation + quotes), verify it works, then add Phase 2 in a subsequent update.

---

## RVB Progressive Degradation (v2.2.0)

### Overview

When Real Vehicle Breakdowns (RVB) mod is installed, the Workhorse/Lemon DNA system extends to affect RVB's part lifetime system. This creates a **unified progressive degradation** where both UsedPlus reliability AND RVB part health respect the vehicle's hidden DNA.

### The Core Concept: Legendary Workhorses Last Forever

The key insight is that **legendary workhorses (DNA ≥ 0.90) can effectively last forever** if properly maintained:
- They are **immune to repair degradation** - repairing doesn't wear them down
- They take **reduced breakdown damage** - when things do fail, damage is minimal
- As long as they're kept repaired and avoid breakdowns, they maintain full capacity indefinitely

Meanwhile, **lemons spiral downward** - each repair and breakdown makes them worse, creating a "death spiral" where frequent problems lead to faster degradation which leads to more problems.

### How It Works

#### Phase 1: Initial DNA Multiplier (At Purchase)

When a used vehicle is purchased, DNA affects initial RVB part lifetimes:

```lua
-- DNA 0.0 (lemon):     0.6x lifetime = parts fail faster from the start
-- DNA 0.5 (average):   1.0x lifetime = normal behavior
-- DNA 1.0 (workhorse): 1.4x lifetime = parts last 40% longer

local initialMultiplier = 0.6 + (workhorseLemonScale * 0.8)
```

#### Phase 2: Repair Degradation (Ongoing)

Each time a vehicle is repaired (through RVB Workshop or vanilla repair):

```lua
-- Legendary workhorses (DNA >= 0.90): IMMUNE - no degradation
-- Others: Lose 0-2% of part lifetime per repair

if workhorseLemonScale < 0.90 then
    local degradation = (1 - workhorseLemonScale) * 0.02
    part.tmp_lifetime = part.tmp_lifetime * (1 - degradation)
end

-- Lemon: -2% per repair
-- Average: -1% per repair
-- Workhorse (0.80): -0.4% per repair
-- Legendary (0.90+): 0% per repair
```

#### Phase 3: Breakdown Degradation (On Fault)

When an RVB part fails (fault occurs):

```lua
-- Everyone takes damage, but lemons take more
local baseDegradation = 0.03  -- 3% base
local lemonBonus = (1 - workhorseLemonScale) * 0.05  -- 0-5% extra
local totalDegradation = baseDegradation + lemonBonus

-- Legendary workhorses (DNA >= 0.95): Only 30% of normal damage
if workhorseLemonScale >= 0.95 then
    totalDegradation = totalDegradation * 0.3
end

-- Lemon: -8% per breakdown
-- Average: -5.5% per breakdown
-- Workhorse: -3.5% per breakdown
-- Legendary: -2.4% per breakdown
```

### Long-Term Projections

After 20 repairs and 5 breakdowns:

| Vehicle Type | Repair Loss | Breakdown Loss | Final Lifetime | Fate |
|--------------|-------------|----------------|----------------|------|
| Lemon (DNA 0.0) | ~33% | ~34% | ~44% remaining | Dying |
| Average (DNA 0.5) | ~18% | ~25% | ~61% remaining | Worn |
| Workhorse (DNA 0.9) | ~4% | ~16% | ~80% remaining | Good |
| **Legendary (DNA 1.0)** | **0%** | ~11% | **~89% remaining** | **Excellent** |

### Legendary Workhorse Immortality

A legendary workhorse (DNA ≥ 0.95) that **never breaks down** loses **ZERO lifetime**:

```
Year 1:  tmp_lifetime = 1400h, maintained, no breakdowns
Year 5:  tmp_lifetime = 1400h, maintained, no breakdowns
Year 10: tmp_lifetime = 1400h, maintained, no breakdowns
Year 50: tmp_lifetime = 1400h, STILL PERFECT!
```

This creates a powerful incentive to:
1. Search for high-quality vehicles (Excellent tier has ~40% workhorse chance)
2. Keep workhorses well-maintained to prevent breakdowns
3. Sell lemons before they become money pits

### Affected Systems

| System | What Degrades | Effect of Degradation |
|--------|---------------|----------------------|
| **RVB Parts** | `tmp_lifetime` per part | Shorter time between breakdowns |
| **UsedPlus Reliability** | `maxReliabilityCeiling` | Lower max achievable reliability after repair |
| **UsedPlus Components** | `maxEngineDurability`, etc. | Reduced component performance, capped repair |

### New Schema Fields (v2.2.0)

```lua
-- Component Durability (progressive degradation)
spec.maxEngineDurability = 1.0      -- Max achievable engine durability
spec.maxHydraulicDurability = 1.0   -- Max achievable hydraulic durability
spec.maxElectricalDurability = 1.0  -- Max achievable electrical durability

-- RVB Integration Tracking
spec.rvbLifetimeMultiplier = 1.0    -- Initial DNA-based multiplier applied
spec.rvbLifetimesApplied = false    -- Whether initial multiplier has been applied
spec.rvbTotalDegradation = 0        -- Cumulative degradation from repairs/breakdowns
spec.rvbRepairCount = 0             -- Number of RVB repairs performed
spec.rvbBreakdownCount = 0          -- Number of RVB breakdowns suffered
```

### Key Functions

**ModCompatibility.lua:**
- `applyDNAToRVBLifetimes(vehicle)` - Applies initial DNA multiplier to RVB parts
- `applyRVBRepairDegradation(vehicle)` - Called when repair completes
- `applyRVBBreakdownDegradation(vehicle, partKey)` - Called when fault occurs

**UsedPlusMaintenance.lua:**
- `applyRepairDegradation(vehicle)` - Reduces UsedPlus component durabilities
- `applyBreakdownDegradation(vehicle, component)` - Breakdown damage to specific component

**RVBWorkshopIntegration.lua:**
- `hookServiceButton(dialog)` - Catches RVB service button for degradation
- `checkForNewFaults(vehicle)` - Monitors fault state transitions
- `initializeFaultTracking(vehicle)` - Establishes baseline fault states

### Edge Cases Handled

1. **Existing vehicles**: On load, check `rvbLifetimesApplied == false`, apply initial multiplier
2. **RVB installed later**: Deferred sync applies multiplier when RVB becomes available
3. **Difficulty change**: Re-apply initial multiplier (degradation persists)
4. **Multiplayer**: Only server modifies lifetimes; RVB's network code syncs
5. **Vehicle sold/removed**: Fault tracking cleaned up to prevent memory leaks

---

## Changelog

### v2.2.0 (2026-01-11)
- **RVB Progressive Degradation System** - DNA now affects RVB part lifetimes
  - Initial DNA multiplier: 0.6x (lemon) to 1.4x (workhorse) applied at purchase
  - Repair degradation: 0-2% lifetime loss per repair (legendary workhorses immune)
  - Breakdown degradation: 3-8% lifetime loss per fault (lemons lose more)
  - Legendary workhorse immunity: DNA ≥ 0.90 immune to repair wear, DNA ≥ 0.95 reduced breakdown damage
- **Component Durability System** - Per-component max durability tracking
  - `maxEngineDurability`, `maxHydraulicDurability`, `maxElectricalDurability`
  - Repairs capped by BOTH overall ceiling AND component durability
  - Failed components take 1.5x extra durability damage
- **Fault Monitoring** - Real-time RVB fault state tracking
  - Detects fault state transitions during gameplay
  - Applies breakdown degradation when parts fail
  - Cleaned up when vehicles are sold/removed
- **New functions**: `applyDNAToRVBLifetimes()`, `applyRVBRepairDegradation()`, `applyRVBBreakdownDegradation()`
- **Service button hook**: RVB Service button now applies degradation

### v1.4.1 (PROPOSED)
- Added Phase 2 enhancement section (damage/wear rate modifiers)
- Added 10 "country" style quotes (1 per tier)
- Updated quote distribution: 2 technical, 2 superstitious, 1 country per tier

### v1.4.0 (PROPOSED)
- Initial design document created
- Core mechanics defined
- Implementation plan outlined
- Balance considerations documented

---

*Document maintained by Claude & Samantha*
*Design Status: PENDING IMPLEMENTATION*
*Last reviewed: 2025-12-27*
