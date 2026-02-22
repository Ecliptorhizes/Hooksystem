local Rarity = require(script.Parent.util.Types.Rarity)
local ShopTypes = require(script.Parent.util.Types.ShopTypes)

type ShopItem = ShopTypes.ShopItem

local Weapons: { [string]: ShopItem } = {
    BasicSniper = {
        id = "BasicSniper",
        name = "Basic Sniper",
        itemType = "weapon",
        rarity = "Common",
        price = 500,
    },
    HyperwaveSniper = {
        id = "HyperwaveSniper",
        name = "Hyperwave Sniper",
        itemType = "weapon",
        rarity = "Rare",
        price = 2500,
    },
    MoltenSniper = {
        id = "MoltenSniper",
        name = "Molten Sniper",
        itemType = "weapon",
        rarity = "Legendary",
        price = 10000,
    },
}


local Skins: { [string]: ShopItem } = {
    -- Be adding Skin Names
}


local function getItem(id: string): ShopItem?
    return Weapons[id] or Skins[id]
end

local function getCatalog(): { ShopItem }
    local catalog = {}
    for _, item in Weapons do
        table.insert(catalog, item)
    end
    for _, item in Skins do
        table.insert(catalog, item)
    end
    return catalog
end

return {
    Weapons = Weapons,
    Skins = Skins,
    getItem = getItem,
    getCatalog = getCatalog,
}

