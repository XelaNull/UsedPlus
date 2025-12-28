# FS25_UsedPlus - Complete Feature List

A comprehensive finance, maintenance, and marketplace overhaul for Farming Simulator 25.

---

## CREDIT & FINANCE SYSTEM

### FICO-Style Credit Scoring
* Dynamic credit scores ranging from 300 to 850, modeled after real-world FICO scoring
* Starting score of 500 for new players
* Payment history is the primary factor (up to +250 points)
* Five credit tiers: Excellent (750+), Good (700-749), Fair (650-699), Poor (550-649), Very Poor (<550)
* Credit score directly impacts loan approval, interest rates, and available terms

### Credit Score Impact
* On-time payments gradually increase your credit score
* Missed payments cause rapid credit score drops
* Repossession events severely damage credit standing
* Full credit report available showing payment history and score breakdown

### Vehicle & Equipment Financing
* Finance any vehicle or equipment purchase (1-30 year terms)
* Interest rates based on credit score (lower score = higher rates)
* Monthly automatic payment processing
* Pay extra toward principal at any time
* Early payoff available with no prepayment penalty
* Full amortization schedule visible in deal details

### Cash Loans with Collateral
* Take out general-purpose cash loans against your assets
* Use owned vehicles and equipment as collateral
* Loan amount limited by collateral value
* Collateral seizure if loan defaults after missed payments
* Multiple collateral items can secure a single loan

### Finance Repair & Repaint
* Finance the cost of repairs when short on cash
* Finance repaint costs with monthly payments
* Spread maintenance costs over time instead of paying upfront

---

## FARMLAND

### Land Leasing
* Lease farmland for 1, 3, 5, or 10-year terms
* Shorter terms have higher markup rates (20% for 1 year, 5% for 10 years)
* Monthly lease payments automatically deducted
* Expiration warnings at 3 months, 1 month, and 1 week before end
* Land reverts to NPC ownership upon lease expiration
* Lease renewal option available before expiration

### Land Financing
* Finance farmland purchases over extended terms
* Build equity while using the land
* Lower monthly payment compared to lease-to-own

### Lease Buyout
* Purchase leased land before term ends at discounted rate
* Longer lease terms earn bigger buyout discounts (up to 15% off)
* Credit toward purchase price based on payments already made

---

## VEHICLE MAINTENANCE SYSTEM

### Three-Component Reliability
* **Engine Health**: Affects power output, fuel efficiency, and starting reliability
* **Electrical Health**: Impacts lights, gauges, and electronic systems
* **Hydraulic Health**: Controls implement lift, steering assist, and attachments

### Hidden Reliability Trait
* Each vehicle has a hidden "lemon or workhorse" trait assigned at spawn
* Lemons experience more frequent breakdowns and faster wear
* Workhorses are more reliable with slower degradation
* Mechanic inspection hints at vehicle's reliability class

### Tire System
* Three tire quality tiers: Retread, Normal, Quality
* Tire tread wears over time based on usage and terrain
* Worn tires reduce traction and increase slip
* Flat tires cause steering pull toward the affected side
* Flat tires reduce maximum speed
* Low traction warnings in wet/icy conditions
* Tire service available to replace worn tires

### Fluid Systems
* **Engine Oil**: Depletes with use, low oil causes engine damage
* **Hydraulic Fluid**: Powers implements and steering, leaks cause system failures
* **Fuel**: Fuel leaks drain tank over time when detected
* Leak detection with dashboard warnings
* Fluid service dialog to refill oil and hydraulic fluid

### Mechanic Inspection
* Comprehensive inspection available at dealer or via agent
* Reveals component health percentages
* Shows tire condition and fluid levels
* Hints at hidden reliability trait
* Inspection history tracked per vehicle

### Repair & Maintenance
* Partial repairs available (fix just what you need)
* Partial repaints for cosmetic damage
* Repair history tracked as part of vehicle record
* Breakdown events logged for resale transparency

---

## VEHICLE MALFUNCTIONS

Real consequences for neglecting maintenance:

### Engine Malfunctions
* **Overheating**: Engine temperature rises, power reduces, eventual stall
* **Misfiring**: Random power fluctuations and rough running
* **Stalling**: Engine cuts out unexpectedly, restart required
* **Hard Starting**: Difficulty starting in cold conditions with worn engine

### Electrical Malfunctions
* **Electrical Cutout**: Temporary loss of electrical systems
* **Gauge Failures**: Instrument readings become unreliable
* **Light Flickering**: Headlights and work lights flicker or fail

### Hydraulic Malfunctions
* **Hydraulic Drift**: Implements slowly lower when raised
* **Implement Surge**: Sudden unexpected implement movements
* **PTO Toggle**: Power take-off randomly engages or disengages
* **Hitch Failure**: Attachments may unexpectedly disconnect

### Tire Malfunctions
* **Flat Tire**: Sudden tire failure causing steering pull
* **Slow Leak**: Gradual pressure loss over time
* **Blowout**: High-speed tire failure

### Fuel System Malfunctions
* **Fuel Leak**: Tank slowly drains fuel when parked or running

---

## USED VEHICLE MARKETPLACE

### Agent-Based Vehicle Searching
* Hire an agent to search for specific used vehicles
* **Local Agent**: 1-2 month search, lower fees, smaller selection
* **Regional Agent**: 2-4 month search, moderate fees, better selection
* **National Agent**: 4-6 month search, higher fees, best selection
* Small upfront retainer fee when search begins
* Agent commission built into vehicle price upon purchase

### Search Configuration
* Choose specific vehicle make and model
* Select desired quality level (affects price and condition)
* Agent continues monthly searches until contract ends
* Multiple vehicles accumulate in your portfolio as found
* Browse and purchase from found vehicles at any time

### Used Vehicle Condition
* Condition ranges from Poor to Excellent
* Lower condition = lower price but more repairs needed
* Component health (engine, electrical, hydraulic) varies by condition
* Tire wear and fluid levels reflect actual vehicle state
* Maintenance history available for review before purchase

### Used Vehicle Pricing
* Used prices significantly below new retail
* Price reflects actual condition and component health
* Trade-in available when purchasing (takes your old vehicle)
* Savings tracked in lifetime statistics

---

## VEHICLE SELLING

### Agent-Based Vehicle Sales
* List owned vehicles for sale through agent network
* **Local Agent**: Fastest sales (1-2 months), lowest returns (60-75%)
* **Regional Agent**: Moderate timeline (2-4 months), better returns (75-90%)
* **National Agent**: Longest wait (3-6 months), best returns (90-100%)
* Agent actively markets your vehicle to potential buyers

### Private Sale Option
* No-cost listing similar to vanilla selling
* Instant sale at standard depreciated value
* No agent fees but no price negotiation

### Sale Offers
* Receive offers from interested buyers
* Accept or decline each offer
* Offer amounts based on vehicle condition and market demand
* Multiple offers may come in during listing period
* Offers expire if not responded to promptly

### Trade-In System
* Trade in old vehicle when purchasing new
* Instant disposal - lowest return option (50-65% of sell value)
* Condition impacts trade-in value (damage and wear reduce price)
* Brand loyalty bonus (5% extra for same manufacturer)
* Convenient when upgrading equipment

---

## USER INTERFACE

### Financial Dashboard
* Overview of all active loans and leases
* Payment schedule and upcoming due dates
* Credit score display with rating tier
* Total debt and monthly payment obligations
* Quick access to deal details and payment options

### 30 Custom Dialogs
* Comprehensive UI for all finance, maintenance, and marketplace features
* Consistent styling matching FS25 native interface
* Full keyboard and controller navigation support
* Informative displays with color-coded values

### Shop Integration
* "Finance" and "Lease" buttons in vehicle shop
* "Search Used" option to find pre-owned equipment
* Trade-in option when purchasing
* Condition display for used vehicles

### Map Integration
* "Buy", "Finance", and "Lease" options for farmland from map view
* Repair option when clicking owned vehicles on map

---

## MULTIPLAYER SUPPORT

* Full multiplayer compatibility with server-authoritative logic
* All transactions validated and processed on server
* Network events sync finance data across clients
* Per-farm credit scores and deal tracking
* Shared farm finances visible to farm members

---

## STATISTICS TRACKING

### Lifetime Statistics Per Farm
* Searches started, succeeded, failed, and cancelled
* Total agent fees paid
* Savings from buying used vs new
* Vehicles purchased through used marketplace
* Sales listed and completed
* Total sale proceeds
* Finance deals created and completed
* Total amount financed over time
* Total interest paid

---

## LOCALIZATION

* Full English translation included
* German translation included
* Additional languages: French, Spanish, Italian, Portuguese, Polish, Russian, Chinese, Japanese
