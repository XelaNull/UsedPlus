# UsedPlus Technical Documentation

This folder contains in-depth technical documentation for the UsedPlus mod's core systems.

---

## Quick Navigation

| Document | Description | Audience |
|----------|-------------|----------|
| [ECONOMICS.md](ECONOMICS.md) | Buy/sell pricing model, agent tiers, trade-in formulas | Modders, balance testers |
| [VEHICLE_INSPECTION.md](VEHICLE_INSPECTION.md) | Reliability system, component health, in-game effects | Players, modders |
| [WORKHORSE_LEMON_SCALE.md](WORKHORSE_LEMON_SCALE.md) | Hidden "DNA" system, inspector quotes, long-term reliability | Players, modders |

---

## Document Relationships

```
                     ┌─────────────────────┐
                     │    ECONOMICS.md     │
                     │  (Pricing & Sales)  │
                     └──────────┬──────────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
          ┌─────────▼─────────┐   ┌─────────▼──────────┐
          │ VEHICLE_INSPECTION│   │ WORKHORSE_LEMON    │
          │ (Current Health)  │◄─►│ (Hidden DNA)       │
          └───────────────────┘   └────────────────────┘
```

- **Economics** defines how prices are calculated (base values, discounts, fees)
- **Vehicle Inspection** defines what you CAN see (component health, inspection reports)
- **Workhorse/Lemon** defines what you CAN'T see (hidden quality that affects long-term reliability)

---

## For Players

Start with [VEHICLE_INSPECTION.md](VEHICLE_INSPECTION.md) to understand:
- Why some used vehicles have problems after repair
- What the inspection report tells you
- How to interpret the mechanic's assessment quotes

Then read [WORKHORSE_LEMON_SCALE.md](WORKHORSE_LEMON_SCALE.md) to understand:
- Why some tractors "just keep running" while others are money pits
- How to recognize warning signs before buying

---

## For Modders/Contributors

Start with [ECONOMICS.md](ECONOMICS.md) to understand:
- The mathematical formulas behind all pricing
- How quality tiers, agent tiers, and price tiers interact
- Balance considerations and vanilla deviation analysis

The other two docs contain implementation details and config options.

---

## Related Documentation

- **[../README.md](../README.md)** - User-facing overview and quick start
- **[../FEATURES.md](../FEATURES.md)** - Complete feature list
- **[../COMPATIBILITY.md](../COMPATIBILITY.md)** - Cross-mod compatibility
- **[../DESIGN.md](../DESIGN.md)** - Original design document with system specifications

---

*Last updated: 2025-12-28*
