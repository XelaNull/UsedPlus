# Vehicle Image Display in FS25 Dialogs

**Purpose:** This document explains the correct way to display vehicle/store item images in FS25 GUI dialogs. It analyzes the working pattern from FS25_gameplay_Real_Vehicle_Breakdowns (RVB) and contrasts it with UsedPlus's problematic approach.

**Last Updated:** 2026-01-11
**Status:** Reference Documentation

---

## TL;DR - The Correct Pattern

```xml
<!-- XML Profile Definition -->
<Profile name="myVehicleImage" extends="baseReference" with="anchorTopCenter">
    <size value="180px 180px"/>
    <imageSliceId value="noSlice"/>
</Profile>

<!-- XML Element - Standard Position -->
<Bitmap profile="myVehicleImage" id="vehicleImage" position="-185px 75px"/>
```

```lua
-- Lua: Simple image loading (use unified helper)
UIHelper.Image.set(self.vehicleImage, storeItem)
-- OR direct:
self.vehicleImage:setImageFilename(storeItem.imageFilename)
```

**Key Points:**
1. Use `imageSliceId="noSlice"` - CRITICAL for correct aspect ratio
2. Use SQUARE dimensions (180x180) - FS25 handles aspect ratio
3. Extend `baseReference`, not specialized image profiles
4. **Standard position: `-185px 75px`** - X=left of center, Y=moves up
5. Simple `setImageFilename()` call - no complex sizing logic

---

## Standard Position: -185px 75px

All UsedPlus dialogs use a consistent vehicle image position:

```xml
<Bitmap profile="*VehicleImage" id="vehicleImage" position="-185px 75px"/>
```

**Why these values?**
- **X = -185px**: Centers the 180px image in the left half of a ~720px container
  - Container center = 0px
  - Left half center = -180px (approximately)
  - Small offset for visual balance = -185px
- **Y = 75px**: Moves the image UP to vertically center in ~100px container
  - With `anchorTopCenter`, positive Y moves the element UP
  - With `noSlice`, visible image content (~90px for 2:1 source) is centered in 180px element
  - Y=75px compensates for the ~45px top padding created by aspect ratio preservation
  - Value empirically tested for optimal visual alignment

**Exception:** Trade-in thumbnails use `-250px -20px` (different context, may need separate tuning)

---

## The Problem: Why UsedPlus Images Look Wrong

Throughout UsedPlus, vehicle preview images display incorrectly:
- Images appear stretched horizontally
- Aspect ratios are distorted
- Different dialogs show different levels of distortion
- Complex sizing calculations don't fix the problem

**Root Causes (UsedPlus's Problematic Approach):**

1. **Missing `imageSliceId="noSlice"`** - Without this, FS25's GUI system may slice/stretch the image to fill the element
2. **Non-square dimensions** - Using sizes like `210x140` or `210x105` forces FS25 to stretch the source image
3. **Complex helper functions** - `UIHelper.Image.setStoreItemImageScaled()` tries to calculate sizes, but mathematical approaches don't work reliably
4. **Wrong base profile** - Extending `fs25_vehiclesDetailsImage` may inherit unwanted behavior

---

## The Solution: RVB's Working Pattern

The Real Vehicle Breakdowns mod displays vehicle images perfectly. Here's exactly how they do it:

### XML Profile (rvbWorkshopDialog.xml, line 118-122)

```xml
<Profile name="rvb_vehicleImage" extends="baseReference" with="anchorTopStretchingX pivotTopCenter">
    <position value="25px 0px"/>
    <size value="200px 200px"/>
    <imageSliceId value="noSlice"/>
</Profile>
```

**Critical Attributes:**

| Attribute | Value | Purpose |
|-----------|-------|---------|
| `extends` | `baseReference` | Basic image element - no inherited complexity |
| `with` | `anchorTopStretchingX pivotTopCenter` | Positioning relative to container |
| `size` | `200px 200px` | **SQUARE dimensions** - FS25 handles aspect ratio |
| `imageSliceId` | `noSlice` | **CRITICAL** - Prevents image slicing/stretching |

### XML Element Usage

```xml
<Bitmap profile="rvb_vehicleImage" visible="true" id="vehicleImage"/>
```

Simple Bitmap element with the profile - no inline size overrides.

### Lua Code (rvbWorkshopDialog.lua, line 107)

```lua
self.vehicleImage:setImageFilename(vehicle:getImageFilename())
```

That's it! Just one line:
- `vehicle:getImageFilename()` returns the path to the vehicle's store image
- `setImageFilename()` loads the image
- **No setSize() calls**
- **No aspect ratio calculations**
- **No complex helper functions**

---

## What NOT To Do (UsedPlus Counter-Examples)

### UsedPlus XML Profile (UsedSearchDialog.xml, line 283-285)

```xml
<!-- PROBLEMATIC - Missing imageSliceId, non-square dimensions -->
<Profile name="usItemImage" extends="fs25_vehiclesDetailsImage" with="anchorTopCenter">
    <size value="210px 140px"/>
</Profile>
```

**Problems:**
1. No `imageSliceId="noSlice"` attribute
2. Non-square `210x140` dimensions
3. Extends `fs25_vehiclesDetailsImage` instead of `baseReference`

### UsedPlus Lua Code (UIHelper.lua, line 364-423)

```lua
-- PROBLEMATIC - Overly complex helper function
function UIHelper.Image.setStoreItemImageScaled(imageElement, storeItem, maxWidth, maxHeight)
    -- 60 lines of complex logic that doesn't reliably work
    -- Mathematical calculations for screen aspect ratio compensation
    -- Multiple attempts at different sizing approaches
    -- Comments admitting "Theoretical calculations (screen aspect ratio compensation) failed"
end
```

**Problems:**
1. Complex sizing calculations don't work reliably in FS25's coordinate system
2. Tries to compensate for aspect ratio mathematically - which fails
3. Comments in the code itself acknowledge the approach doesn't work
4. Uses `setSize()` calls which can conflict with profile settings

---

## Comparison Table

| Aspect | RVB (Reference) | UsedPlus (Current Standard) |
|--------|-----------------|------------------------------|
| Base Profile | `baseReference` | `baseReference` |
| Dimensions | `200px 200px` (square) | `180px 180px` (square, 10% smaller) |
| `imageSliceId` | `noSlice` | `noSlice` |
| Anchoring | `anchorTopStretchingX pivotTopCenter` | `anchorTopCenter` |
| Position | varies | `-185px 75px` (standardized) |
| Lua Loading | `setImageFilename()` only | `UIHelper.Image.set()` or `setImageFilename()` |
| Result | **Perfect display** | **Perfect display** |

---

## How to Fix UsedPlus Dialogs

### Step 1: Update XML Profile Definition

Replace all vehicle image profiles with the correct pattern:

```xml
<!-- BEFORE (Wrong) -->
<Profile name="usItemImage" extends="fs25_vehiclesDetailsImage" with="anchorTopCenter">
    <size value="210px 140px"/>
</Profile>

<!-- AFTER (Correct) -->
<Profile name="usItemImage" extends="baseReference" with="anchorTopCenter">
    <size value="180px 180px"/>
    <imageSliceId value="noSlice"/>
</Profile>

<!-- Element positioning -->
<Bitmap profile="usItemImage" id="itemImage" position="-185px 75px"/>
```

### Step 2: Simplify Lua Loading

Replace complex helper calls with simple `setImageFilename()`:

```lua
-- BEFORE (Complex, unreliable)
if self.itemImage then
    UIHelper.Image.setStoreItemImageScaled(self.itemImage, storeItem, 210, 105)
end

-- AFTER (Simple, works)
if self.itemImage and storeItem then
    local imagePath = storeItem.imageFilename or storeItem.imageFilenameFallback
    if imagePath then
        self.itemImage:setImageFilename(imagePath)
    end
end
```

### Step 3: Update UIHelper (Optional)

If using UIHelper.Image, simplify `setStoreItemImage()`:

```lua
function UIHelper.Image.setStoreItemImage(imageElement, storeItem)
    if not imageElement or not storeItem then
        return false
    end

    local imagePath = storeItem.imageFilename or storeItem.imageFilenameFallback
    if imagePath and imagePath ~= "" then
        imageElement:setImageFilename(imagePath)
        return true
    end
    return false
end

-- Remove setStoreItemImageScaled entirely - it's not needed
```

---

## Implementation Checklist

When adding a vehicle image to a new dialog:

- [ ] Profile extends `baseReference`
- [ ] Profile has `with="anchorTopCenter"`
- [ ] Profile has `size="180px 180px"` (SQUARE)
- [ ] Profile has `imageSliceId="noSlice"` (CRITICAL)
- [ ] Element positioned at `-185px 75px`
- [ ] XML uses `<Bitmap profile="..." id="..."/>` element
- [ ] Lua uses `UIHelper.Image.set()` or simple `setImageFilename()` call
- [ ] Lua does NOT call `setSize()` after loading
- [ ] Lua does NOT use complex aspect ratio calculations

---

## Why Square Dimensions?

FS25 store item images are typically 512x256 (2:1 aspect ratio). Using a square container (180x180) with `imageSliceId="noSlice"` tells FS25:

1. "Here's a 180x180 box for the image"
2. "Don't slice or stretch it to fill"
3. FS25 automatically fits the image while preserving aspect ratio
4. The 2:1 image displays within the square, with ~45px padding above/below
5. Y=75px compensates for this padding to visually center the image

This is **much simpler** than trying to calculate the exact dimensions mathematically.

---

## Files to Update

The following UsedPlus files display vehicle images and should be updated to use the correct pattern:

| File | Dialog Name |
|------|-------------|
| `gui/UsedSearchDialog.xml` | Used Equipment Search |
| `gui/InspectionReportDialog.xml` | Inspection Report |
| `gui/UnifiedPurchaseDialog.xml` | Purchase/Finance Dialog |
| `gui/SaleOfferDialog.xml` | Sale Offer |
| `gui/SaleListingDetailsDialog.xml` | Sale Listing Details |
| `gui/UsedVehiclePreviewDialog.xml` | Used Vehicle Preview |
| `gui/MaintenanceReportDialog.xml` | Maintenance Report |
| `gui/DealDetailsDialog.xml` | Deal Details |

---

## Reference Files

**Working Example (RVB):**
- `C:\Users\mrath\Downloads\FS25_Mods_Extracted\FS25_gameplay_Real_Vehicle_Breakdowns\gui\dialogs\rvbWorkshopDialog.xml`
- `C:\Users\mrath\Downloads\FS25_Mods_Extracted\FS25_gameplay_Real_Vehicle_Breakdowns\scripts\gui\dialogs\rvbWorkshopDialog.lua`

**UsedPlus Files to Fix:**
- `C:\Users\mrath\OneDrive\Documents\My Games\FarmingSimulator2025\mods\FS25_UsedPlus\src\utils\UIHelper.lua`
- All XML files in `gui/` directory with vehicle image elements

---

## Key Takeaway

**Don't try to be clever with image sizing math.** FS25's GUI system has built-in aspect ratio handling via `imageSliceId="noSlice"`. Trust the framework:

1. Square container
2. `noSlice` attribute
3. Simple `setImageFilename()` call
4. Let FS25 handle the rest

This approach is simpler, more reliable, and produces correct results every time.
