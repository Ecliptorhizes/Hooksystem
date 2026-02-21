export type Rarity = "Common" | "Uncommon" | "Rare" | "Legendary"

local RarityOrder: { [Rarity]: number } = {
    Common = 1,
    Uncommon = 2,
    Rare = 3,
    Epic = 4,
    Legendary = 5,
}

return {
    RarityOrder = RarityOrder,
}
