-- data/charmGear.lua
-- BST charm-time gear table (CHARM_TIME bonus lookup, static data only).
-- Each entry: item ID → CHARM_TIME bonus points (5% per point to charm duration).
-- Source: PetMe petBSTCharm.lua (HorizonXI-verified item IDs).
-- Add new HorizonXI BST gear entries here as they are discovered.

local CHARM_GEAR = {
    [17936] = 1, -- De Saintre's Axe
    [17950] = 2, -- Marid Ancus
    [12517] = 4, -- Beast Helm
    [15157] = 5, -- Bison Warbonnet
    [15158] = 6, -- Brave's Warbonnet
    [16104] = 5, -- Khimaira Bonnet
    [16105] = 6, -- Stout Bonnet
    [15080] = 5, -- Monster Helm
    [15233] = 4, -- Beast Helm +1
    [15253] = 5, -- Monster Helm +1
    [12646] = 5, -- Beast Jackcoat
    [14418] = 5, -- Bison Jacket
    [14419] = 6, -- Brave's Jacket
    [14566] = 5, -- Khimaira Jacket
    [14567] = 6, -- Stout Jacket
    [15095] = 6, -- Monster Jackcoat
    [14481] = 6, -- Beast Jackcoat +1
    [14508] = 7, -- Monster Jackcoat +1
    [13969] = 3, -- Beast Gloves
    [14850] = 5, -- Bison Wristbands
    [14851] = 6, -- Brave's Wristbands
    [14981] = 5, -- Khimaira Wristbands
    [14982] = 6, -- Stout Wristbands
    [14898] = 3, -- Beast Gloves +1
    [15110] = 4, -- Monster Gloves
    [14917] = 4, -- Monster Gloves +1
    [14222] = 6, -- Beast Trousers
    [14319] = 5, -- Bison Kecks
    [14320] = 6, -- Brave's Kecks
    [15645] = 5, -- Khimaira Kecks
    [15646] = 6, -- Stout Kecks
    [15125] = 2, -- Monster Trousers
    [15569] = 6, -- Beast Trousers +1
    [15588] = 2, -- Monster Trousers +1
    [14097] = 2, -- Beast Gaiters
    [15307] = 5, -- Bison Gamashes
    [15308] = 6, -- Brave's Gamashes
    [15731] = 5, -- Khimaira Gamashes
    [15732] = 6, -- Stout Gamashes
    [15360] = 2, -- Beast Gaiters +1
    [15140] = 3, -- Monster Gaiters
    [15673] = 3, -- Monster Gaiters +1
    [14658] = 4, -- Atlaua's Ring
    [13667] = 5, -- Trimmer's Mantle (HorizonXI /BST)
}

return { CHARM_GEAR = CHARM_GEAR }
