export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

export type ShoptItemType = "weapon" | "skin"

export type ShopItem = {
    id: string,
    name: string, 
    itemType: stopItemType,
    rarity: Rarity,
    price: number,
}

export type WeaponItem = ShopItem & {
    itemType: "weapon",
}

export type SkinItem = ShoptItem & {
    itemType: "skin",
    weaponId: string,
}

return {}
