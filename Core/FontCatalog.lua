-- Static catalog of bundled fonts exposed in configuration dropdowns.

local _, ns = ...

-- Bundled fonts that should always appear in the font dropdown.
ns.FontCatalog = {
    list = {
        { key = "expressway", label = "Expressway", path = "Interface\\AddOns\\mummuFrames\\Fonts\\expressway.ttf" },
        { key = "Fredoka_SemiBold", label = "Fredoka Semi Bold", path = "Interface\\AddOns\\mummuFrames\\Fonts\\Fredoka-SemiBold.ttf" },
    },
}
