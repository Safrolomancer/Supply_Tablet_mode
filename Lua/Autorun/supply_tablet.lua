if SERVER then return end

local args = table.pack(...)

local function detectModPath(argPath)
    if argPath ~= nil and tostring(argPath) ~= "" then
        return tostring(argPath):gsub("\\", "/")
    end

    if debug ~= nil and debug.getinfo ~= nil then
        local info = debug.getinfo(1, "S")
        local source = info ~= nil and tostring(info.source or "") or ""

        if source:sub(1, 1) == "@" then
            local scriptPath = source:sub(2):gsub("\\", "/")
            return scriptPath:match("^(.*)/Lua/Autorun/[^/]+%.lua$")
        end
    end

    return nil
end

local modPath = detectModPath(args[1])

SupplyTablet = SupplyTablet or {}
SupplyTablet.purchases = SupplyTablet.purchases or {}

pcall(function()
    if LuaUserData ~= nil and Descriptors ~= nil then
        LuaUserData.MakeFieldAccessible(Descriptors["Barotrauma.Items.Components.CustomInterface"], "originalElement")
        LuaUserData.MakeFieldAccessible(Descriptors["Barotrauma.Items.Components.ItemComponent"], "item")
    end
end)

local ok, loadError = false, "mod path unavailable"

if modPath ~= nil and tostring(modPath) ~= "" then
    ok, loadError = pcall(function()
        dofile(modPath .. "/Lua/supply_items.lua")
    end)
end

if not ok then
    print("[Supply Tablet] Could not load item catalog: " .. tostring(loadError))
end

SupplyTabletCatalog = SupplyTabletCatalog or {}

local saveFile = modPath ~= nil and (modPath .. "/supply_tablet_data.lua") or nil
local defaultDataFile = modPath ~= nil and (modPath .. "/Lua/default_purchases.lua") or nil

local state = {
    view = "intro",
    search = "",
    purchaseSearch = "",
    group = "all",
    merchant = "any",
    lastStatus = "Terminal ready. Open a manifest or scan the catalog.",
    selectedItem = nil,
    selectedPurchase = nil,
    itemAllocation = "Submarine storage",
    itemAmount = "1",
    itemCost = "",
    itemReason = "Needed for next station",
    crewName = "",
    crewAllocation = "Crew roster",
    crewAmount = "1",
    crewCost = "1000",
    crewType = "Assistant",
    crewLevel = "1",
    editName = "",
    editAllocation = "",
    editAmount = "",
    editCost = "",
    editReason = "",
    editCrewType = "",
    editCrewLevel = ""
}

local groups = {
    { text = "All categories", value = "all" },
    { text = "Medical", value = "medical" },
    { text = "Weapons", value = "weapons" },
    { text = "Ammo", value = "ammo" },
    { text = "Fuel / Oxygen", value = "fuel" },
    { text = "Equipment", value = "equipment" },
    { text = "Materials", value = "materials" },
    { text = "Tools / Other", value = "tools" }
}

local merchants = {
    { text = "Any merchant", value = "any" },
    { text = "Outpost", value = "outpost" },
    { text = "City", value = "city" },
    { text = "Research", value = "research" },
    { text = "Military", value = "military" },
    { text = "Mine", value = "mine" },
    { text = "Engineering", value = "engineering" },
    { text = "Medical", value = "medical" },
    { text = "Armory", value = "armory" },
    { text = "Clown", value = "clown" },
    { text = "Nightclub", value = "nightclub" },
    { text = "Husk", value = "husk" }
}

local quickKits = {
    {
        text = "MED STARTER",
        allocation = "Medical cabinet",
        reason = "Basic emergency medicine",
        ids = { "antibleeding1", "antidama1", "antibloodloss2", "antibiotics", "antirad" }
    },
    {
        text = "AMMO RESTOCK",
        allocation = "Armory",
        reason = "Ammo restock before next mission",
        ids = { "coilgunammobox", "railgunshell", "revolverround", "smgmagazine", "shotgunshell" }
    },
    {
        text = "FUEL / TOOLS",
        allocation = "Engineering",
        reason = "Repair and oxygen basics",
        ids = { "oxygentank", "weldingfueltank", "batterycell", "wrench", "screwdriver" }
    }
}

local function normalize(text)
    return tostring(text or ""):lower():gsub("[^a-z0-9]", "")
end

local function trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parsePositiveInt(text, fallback)
    local value = tonumber(trim(text))

    if value == nil or value < 1 then
        return fallback or 1
    end

    return math.floor(value)
end

local function setStatus(text)
    state.lastStatus = tostring(text or "")
end

local function escapeLuaString(text)
    text = tostring(text or "")
    text = text:gsub("\\", "\\\\")
    text = text:gsub("\"", "\\\"")
    text = text:gsub("\n", "\\n")
    text = text:gsub("\r", "\\r")
    return text
end

local function contains(text, search)
    search = tostring(search or ""):lower()

    if search == "" then
        return true
    end

    return tostring(text or ""):lower():find(search, 1, true) ~= nil
end

local function shortText(text, maxLength)
    text = tostring(text or "")

    if #text <= maxLength then
        return text
    end

    return text:sub(1, maxLength - 3) .. "..."
end

local function itemPrice(item)
    return tonumber(item and (item.averagePrice or item.basePrice) or 0) or 0
end

local function purchaseTotal(purchase)
    return (tonumber(purchase.amount) or 0) * (tonumber(purchase.cost) or 0)
end

local palette = {
    title = Color(221, 232, 165, 255),
    section = Color(111, 210, 190, 255),
    text = Color(186, 207, 186, 255),
    dim = Color(138, 160, 145, 255),
    money = Color(238, 210, 122, 255),
    good = Color(115, 225, 145, 255),
    warning = Color(238, 156, 104, 255)
}

local function paintText(component, color)
    if component ~= nil and color ~= nil then
        pcall(function()
            component.TextColor = color
        end)
    end

    return component
end

local function searchableItemText(item)
    return table.concat({
        item.name or "",
        item.id or "",
        item.category or "",
        item.tags or "",
        item.aliases or "",
        item.soldAt or ""
    }, " ")
end

local function matchesItemSearch(item, search)
    local cleanSearch = trim(tostring(search or ""):lower())

    if cleanSearch == "" then
        return true
    end

    local rawHaystack = searchableItemText(item):lower()
    local normalizedHaystack = normalize(rawHaystack)

    for term in cleanSearch:gmatch("%S+") do
        local normalizedTerm = normalize(term)
        local rawMatch = rawHaystack:find(term, 1, true) ~= nil
        local normalizedMatch = normalizedTerm ~= "" and normalizedHaystack:find(normalizedTerm, 1, true) ~= nil

        if not rawMatch and not normalizedMatch then
            return false
        end
    end

    return true
end

local function matchesMerchant(item)
    if state.merchant == "any" then
        return true
    end

    return contains(item.soldAt, state.merchant) or
           contains(item.soldAt, "all merchants") or
           contains(item.soldAt, "any merchant")
end

local function matchesItemFilters(item)
    if state.group ~= "all" and item.group ~= state.group then
        return false
    end

    return matchesMerchant(item) and matchesItemSearch(item, state.search)
end

local function itemMatchScore(item)
    local search = normalize(state.search)

    if search == "" then
        return 0
    end

    local name = normalize(item.name)
    local id = normalize(item.id)
    local aliases = normalize(item.aliases)
    local category = normalize(item.category)
    local tags = normalize(item.tags)

    if search == name or search == id or search == aliases then
        return 1000
    end

    if name:sub(1, #search) == search or id:sub(1, #search) == search then
        return 850
    end

    if name:find(search, 1, true) or id:find(search, 1, true) then
        return 750
    end

    if category:find(search, 1, true) then
        return 600
    end

    if tags:find(search, 1, true) or aliases:find(search, 1, true) then
        return 400
    end

    return 100
end

local function getFilteredItems()
    local results = {}

    for _, item in ipairs(SupplyTabletCatalog) do
        if matchesItemFilters(item) then
            table.insert(results, item)
        end
    end

    table.sort(results, function(a, b)
        local scoreA = itemMatchScore(a)
        local scoreB = itemMatchScore(b)

        if scoreA ~= scoreB then
            return scoreA > scoreB
        end

        return tostring(a.name or a.id):lower() < tostring(b.name or b.id):lower()
    end)

    return results
end

local function findItemById(itemId)
    for _, item in ipairs(SupplyTabletCatalog) do
        if item.id == itemId then
            return item
        end
    end

    return nil
end

local function makeItemPurchase(item, allocation, amount, cost, reason)
    return {
        type = "item",
        name = item.name or item.id,
        allocation = trim(allocation) ~= "" and trim(allocation) or "Submarine storage",
        amount = parsePositiveInt(amount, 1),
        cost = parsePositiveInt(cost, itemPrice(item)),
        bought = false,
        reasonToBuy = trim(reason) ~= "" and trim(reason) or "Needed for next station",
        gameIdentifier = item.id or "",
        category = item.category or "",
        soldAt = item.soldAt or ""
    }
end

local function makeCrewPurchase(name, allocation, amount, cost, crewType, level)
    return {
        type = "crew",
        name = trim(name) ~= "" and trim(name) or "Unnamed crew",
        allocation = trim(allocation) ~= "" and trim(allocation) or "Crew roster",
        amount = parsePositiveInt(amount, 1),
        cost = parsePositiveInt(cost, 1000),
        bought = false,
        crewType = trim(crewType) ~= "" and trim(crewType) or "Assistant",
        level = parsePositiveInt(level, 1)
    }
end

local function sanitizePurchase(purchase)
    if type(purchase) ~= "table" then
        return nil
    end

    local purchaseType = purchase.type == "crew" and "crew" or "item"
    local cleaned = {
        type = purchaseType,
        name = trim(purchase.name) ~= "" and trim(purchase.name) or (purchaseType == "crew" and "Unnamed crew" or "Unnamed item"),
        allocation = trim(purchase.allocation) ~= "" and trim(purchase.allocation) or (purchaseType == "crew" and "Crew roster" or "Submarine storage"),
        amount = parsePositiveInt(purchase.amount, 1),
        cost = parsePositiveInt(purchase.cost, 1),
        bought = purchase.bought == true
    }

    if purchaseType == "item" then
        cleaned.reasonToBuy = trim(purchase.reasonToBuy) ~= "" and trim(purchase.reasonToBuy) or "Needed for next station"
        cleaned.gameIdentifier = tostring(purchase.gameIdentifier or "")
        cleaned.category = tostring(purchase.category or "")
        cleaned.soldAt = tostring(purchase.soldAt or "")
    else
        cleaned.crewType = trim(purchase.crewType) ~= "" and trim(purchase.crewType) or "Assistant"
        cleaned.level = parsePositiveInt(purchase.level, 1)
    end

    return cleaned
end

local function setPurchasesFrom(source)
    local cleaned = {}

    if type(source) == "table" then
        for _, purchase in ipairs(source) do
            local sanitized = sanitizePurchase(purchase)

            if sanitized ~= nil then
                table.insert(cleaned, sanitized)
            end
        end
    end

    SupplyTablet.purchases = cleaned
end

local function savePurchases()
    if saveFile == nil then
        print("[Supply Tablet] Could not save purchase data because the mod path is unknown.")
        return false
    end

    local tempSaveFile = saveFile .. ".tmp"
    local file = io.open(tempSaveFile, "w")

    if file == nil then
        print("[Supply Tablet] Could not save purchase data to " .. tostring(tempSaveFile))
        return false
    end

    file:write("return {\n")

    for _, rawPurchase in ipairs(SupplyTablet.purchases) do
        local purchase = sanitizePurchase(rawPurchase)

        if purchase ~= nil then
            file:write("    {\n")
            file:write("        type = \"" .. escapeLuaString(purchase.type) .. "\",\n")
            file:write("        name = \"" .. escapeLuaString(purchase.name) .. "\",\n")
            file:write("        allocation = \"" .. escapeLuaString(purchase.allocation) .. "\",\n")
            file:write("        amount = " .. tostring(parsePositiveInt(purchase.amount, 1)) .. ",\n")
            file:write("        cost = " .. tostring(parsePositiveInt(purchase.cost, 1)) .. ",\n")
            file:write("        bought = " .. tostring(purchase.bought == true) .. ",\n")

            if purchase.type == "item" then
                file:write("        reasonToBuy = \"" .. escapeLuaString(purchase.reasonToBuy) .. "\",\n")
                file:write("        gameIdentifier = \"" .. escapeLuaString(purchase.gameIdentifier) .. "\",\n")
                file:write("        category = \"" .. escapeLuaString(purchase.category) .. "\",\n")
                file:write("        soldAt = \"" .. escapeLuaString(purchase.soldAt) .. "\"\n")
            else
                file:write("        crewType = \"" .. escapeLuaString(purchase.crewType) .. "\",\n")
                file:write("        level = " .. tostring(parsePositiveInt(purchase.level, 1)) .. "\n")
            end

            file:write("    },\n")
        end
    end

    file:write("}\n")
    file:close()

    os.remove(saveFile)

    local renamed, renameError = os.rename(tempSaveFile, saveFile)

    if not renamed then
        print("[Supply Tablet] Could not replace saved purchase data: " .. tostring(renameError))
        return false
    end

    return true
end

local function loadPurchases()
    if saveFile == nil then
        setPurchasesFrom({})
        setStatus("Save path unavailable. Running in temporary checklist mode.")
        return
    end

    local file = io.open(saveFile, "r")

    if file == nil then
        local defaultsOk, defaults = false, nil

        if defaultDataFile ~= nil then
            defaultsOk, defaults = pcall(dofile, defaultDataFile)
        end

        if defaultsOk and type(defaults) == "table" then
            setPurchasesFrom(defaults)
            print("[Supply Tablet] Imported " .. tostring(#SupplyTablet.purchases) .. " default purchases.")
        else
            setPurchasesFrom({})
        end

        return
    end

    file:close()

    local loadedOk, loaded = pcall(dofile, saveFile)

    if loadedOk and type(loaded) == "table" then
        setPurchasesFrom(loaded)
        print("[Supply Tablet] Loaded " .. tostring(#SupplyTablet.purchases) .. " saved purchases.")
    else
        setPurchasesFrom({})
        print("[Supply Tablet] Could not load saved purchases: " .. tostring(loaded))
        setStatus("Save file could not be read. Started with an empty manifest.")
    end
end

local function addPurchase(purchase)
    local sanitized = sanitizePurchase(purchase)

    if sanitized == nil then
        setStatus("Could not add purchase: invalid record.")
        return
    end

    table.insert(SupplyTablet.purchases, sanitized)
    state.selectedPurchase = #SupplyTablet.purchases
    state.editName = sanitized.name
    state.editAllocation = sanitized.allocation
    state.editAmount = tostring(sanitized.amount)
    state.editCost = tostring(sanitized.cost)
    state.editReason = sanitized.reasonToBuy or ""
    state.editCrewType = sanitized.crewType or ""
    state.editCrewLevel = tostring(sanitized.level or 1)
    savePurchases()
    setStatus("Added " .. tostring(sanitized.name) .. " to the manifest.")
end

local function removePurchase(index)
    if index ~= nil and SupplyTablet.purchases[index] ~= nil then
        local removedName = tostring(SupplyTablet.purchases[index].name or "purchase")
        table.remove(SupplyTablet.purchases, index)
        state.selectedPurchase = nil
        savePurchases()
        setStatus("Removed " .. removedName .. " from the manifest.")
    end
end

local function selectPurchase(index)
    local purchase = SupplyTablet.purchases[index]

    if purchase == nil then
        state.selectedPurchase = nil
        return
    end

    state.selectedPurchase = index
    state.editName = purchase.name or ""
    state.editAllocation = purchase.allocation or ""
    state.editAmount = tostring(purchase.amount or 1)
    state.editCost = tostring(purchase.cost or 1)
    state.editReason = tostring(purchase.reasonToBuy or "")
    state.editCrewType = tostring(purchase.crewType or "")
    state.editCrewLevel = tostring(purchase.level or 1)
end

local function applySelectedEdit()
    local purchase = SupplyTablet.purchases[state.selectedPurchase]

    if purchase == nil then
        return
    end

    purchase.name = trim(state.editName) ~= "" and trim(state.editName) or purchase.name
    purchase.allocation = trim(state.editAllocation) ~= "" and trim(state.editAllocation) or purchase.allocation
    purchase.amount = parsePositiveInt(state.editAmount, purchase.amount)
    purchase.cost = parsePositiveInt(state.editCost, purchase.cost)

    if purchase.type == "item" then
        purchase.reasonToBuy = trim(state.editReason) ~= "" and trim(state.editReason) or purchase.reasonToBuy
    elseif purchase.type == "crew" then
        purchase.crewType = trim(state.editCrewType) ~= "" and trim(state.editCrewType) or purchase.crewType
        purchase.level = parsePositiveInt(state.editCrewLevel, purchase.level)
    end

    savePurchases()
    setStatus("Updated " .. tostring(purchase.name or "purchase") .. ".")
end

local function purchaseMatchesSearch(purchase)
    local search = trim(state.purchaseSearch):lower()

    if search == "" then
        return true
    end

    local text = table.concat({
        purchase.name or "",
        purchase.allocation or "",
        purchase.reasonToBuy or "",
        purchase.category or "",
        purchase.gameIdentifier or "",
        purchase.soldAt or "",
        purchase.crewType or ""
    }, " "):lower()

    return text:find(search, 1, true) ~= nil or normalize(text):find(normalize(search), 1, true) ~= nil
end

local function getVisiblePurchases()
    local rows = {}

    for index, purchase in ipairs(SupplyTablet.purchases) do
        if purchaseMatchesSearch(purchase) then
            table.insert(rows, { index = index, purchase = purchase })
        end
    end

    return rows
end

local function summary()
    local total = 0
    local boughtTotal = 0
    local notBoughtTotal = 0
    local itemCount = 0
    local crewCount = 0
    local boughtCount = 0

    for _, purchase in ipairs(SupplyTablet.purchases) do
        local rowTotal = purchaseTotal(purchase)
        total = total + rowTotal

        if purchase.type == "item" then
            itemCount = itemCount + 1
        elseif purchase.type == "crew" then
            crewCount = crewCount + 1
        end

        if purchase.bought then
            boughtCount = boughtCount + 1
            boughtTotal = boughtTotal + rowTotal
        else
            notBoughtTotal = notBoughtTotal + rowTotal
        end
    end

    return {
        total = total,
        boughtTotal = boughtTotal,
        notBoughtTotal = notBoughtTotal,
        itemCount = itemCount,
        crewCount = crewCount,
        boughtCount = boughtCount,
        notBoughtCount = #SupplyTablet.purchases - boughtCount
    }
end

local function categorySummary()
    local categories = {}

    for _, purchase in ipairs(SupplyTablet.purchases) do
        if purchase.type == "item" then
            local category = trim(purchase.category) ~= "" and purchase.category or "Unknown"

            if categories[category] == nil then
                categories[category] = { count = 0, total = 0 }
            end

            categories[category].count = categories[category].count + 1
            categories[category].total = categories[category].total + purchaseTotal(purchase)
        end
    end

    local rows = {}

    for category, data in pairs(categories) do
        table.insert(rows, { category = category, count = data.count, total = data.total })
    end

    table.sort(rows, function(a, b)
        return a.total > b.total
    end)

    return rows
end

local function addTitle(parent, text)
    return paintText(GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.052), parent), text, nil, nil, GUI.Alignment.Center), palette.title)
end

local function addSection(parent, text)
    return paintText(GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.044), parent), text, nil, nil, GUI.Alignment.Left), palette.section)
end

local function addText(parent, text)
    return paintText(GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.04), parent), text, nil, nil, GUI.Alignment.Left), palette.text)
end

local function addStatusText(parent, text, color)
    return paintText(GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.04), parent), text, nil, nil, GUI.Alignment.Left), color)
end

local function addButton(parent, text, callback, tooltip)
    local button = GUI.Button(GUI.RectTransform(Vector2(1, 0.058), parent), text, GUI.Alignment.Center, "GUIButtonSmall")
    button.ToolTip = tooltip or ""
    button.OnClicked = function()
        callback()
        return true
    end
    return button
end

local function selectDropDownValue(dropDown, value)
    pcall(function()
        dropDown.SelectItem(value)
    end)
end

local function addTabButtons(parent, rebuild)
    local tabs = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.065), parent), true, GUI.Anchor.CenterLeft)

    local entries = {
        { label = "BOOT", view = "intro" },
        { label = "ADD ITEM", view = "items" },
        { label = "ADD CREW", view = "crew" },
        { label = "PURCHASES", view = "list" },
        { label = "REPORTS", view = "reports" }
    }

    for _, entry in ipairs(entries) do
        local label = state.view == entry.view and ("[" .. entry.label .. "]") or entry.label
        local button = GUI.Button(GUI.RectTransform(Vector2(0.2, 1), tabs.RectTransform), label, GUI.Alignment.Center, "GUIButtonSmall")
        paintText(button.TextBlock, state.view == entry.view and palette.title or palette.section)
        button.OnClicked = function()
            state.view = entry.view
            rebuild()
            return true
        end
    end
end

local function drawIntro(parent, rebuild)
    local data = summary()

    addSection(parent, "EUROPA LOGISTICS TERMINAL")
    addStatusText(parent, "SUPPLY LINK: ONLINE | CATALOG: " .. tostring(#SupplyTabletCatalog) .. " ITEMS | SAVE: " .. (saveFile ~= nil and "LOCAL" or "TEMPORARY"), palette.good)
    addText(parent, "Mission manifest armed for outpost procurement, cargo allocation and roster requests.")
    addText(parent, "Transactions remain under captain and quartermaster authority.")
    addStatusText(parent, "Current budget open: " .. tostring(data.notBoughtTotal) .. " mk | Bought: " .. tostring(data.boughtCount) .. " | Open: " .. tostring(data.notBoughtCount), palette.money)

    addSection(parent, "QUICK ACTIONS")

    local actions = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.075), parent), true, GUI.Anchor.CenterLeft)

    local catalogButton = GUI.Button(GUI.RectTransform(Vector2(0.333, 1), actions.RectTransform), "SCAN CATALOG", GUI.Alignment.Center, "GUIButtonSmall")
    catalogButton.OnClicked = function()
        state.view = "items"
        setStatus("Catalog scanner ready.")
        rebuild()
        return true
    end

    local manifestButton = GUI.Button(GUI.RectTransform(Vector2(0.333, 1), actions.RectTransform), "OPEN MANIFEST", GUI.Alignment.Center, "GUIButtonSmall")
    manifestButton.OnClicked = function()
        state.view = "list"
        setStatus("Purchase manifest opened.")
        rebuild()
        return true
    end

    local reportButton = GUI.Button(GUI.RectTransform(Vector2(0.333, 1), actions.RectTransform), "BUDGET REPORT", GUI.Alignment.Center, "GUIButtonSmall")
    reportButton.OnClicked = function()
        state.view = "reports"
        setStatus("Budget report generated.")
        rebuild()
        return true
    end

    addSection(parent, "WATCH OFFICER NOTES")
    addText(parent, "Allocation channels: medical cabinet, armory, engineering, submarine storage.")
    addText(parent, "Pre-undocking board: unresolved requests remain flagged OPEN.")
end

local function drawItemView(parent, rebuild)
    addSection(parent, "CATALOG SCANNER")

    local searchRow = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.066), parent), true, GUI.Anchor.CenterLeft)

    local searchBox = GUI.TextBox(GUI.RectTransform(Vector2(0.72, 1), searchRow.RectTransform), state.search)
    searchBox.ToolTip = "Search by readable name, identifier, category, tag, alias or merchant."
    searchBox.OnTextChangedDelegate = function(textBox)
        state.search = tostring(textBox.Text or "")
    end
    searchBox.OnEnterPressed = function()
        setStatus("Catalog search refreshed.")
        rebuild()
        return true
    end

    local scanButton = GUI.Button(GUI.RectTransform(Vector2(0.28, 1), searchRow.RectTransform), "SCAN", GUI.Alignment.Center, "GUIButtonSmall")
    scanButton.OnClicked = function()
        setStatus("Catalog search refreshed.")
        rebuild()
        return true
    end

    local groupDrop = GUI.DropDown(GUI.RectTransform(Vector2(1, 0.06), parent), "Category filter", 8, nil, false)
    for _, group in ipairs(groups) do
        groupDrop.AddItem(group.text, group.value)
    end
    selectDropDownValue(groupDrop, state.group)
    groupDrop.OnSelected = function(_, selectedValue)
        state.group = tostring(selectedValue or "all")
        setStatus("Category filter changed.")
        rebuild()
    end

    local merchantDrop = GUI.DropDown(GUI.RectTransform(Vector2(1, 0.06), parent), "Merchant filter", 8, nil, false)
    for _, merchant in ipairs(merchants) do
        merchantDrop.AddItem(merchant.text, merchant.value)
    end
    selectDropDownValue(merchantDrop, state.merchant)
    merchantDrop.OnSelected = function(_, selectedValue)
        state.merchant = tostring(selectedValue or "any")
        setStatus("Merchant filter changed.")
        rebuild()
    end

    local selected = state.selectedItem
    local selectedText = "Selected: none"

    if selected ~= nil then
        selectedText = "Selected: " .. tostring(selected.name or selected.id) .. " | " .. tostring(itemPrice(selected)) .. " mk | " .. tostring(selected.soldAt)
    end

    addText(parent, selectedText)

    local form = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.18), parent), true, GUI.Anchor.CenterLeft)
    local left = GUI.ListBox(GUI.RectTransform(Vector2(0.5, 1), form.RectTransform))
    local right = GUI.ListBox(GUI.RectTransform(Vector2(0.5, 1), form.RectTransform))

    addText(left.Content.RectTransform, "Allocation")
    local allocationBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.32), left.Content.RectTransform), state.itemAllocation)
    allocationBox.OnTextChangedDelegate = function(textBox)
        state.itemAllocation = tostring(textBox.Text or "")
    end

    addText(left.Content.RectTransform, "Amount")
    local amountBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.32), left.Content.RectTransform), state.itemAmount)
    amountBox.OnTextChangedDelegate = function(textBox)
        state.itemAmount = tostring(textBox.Text or "")
    end

    addText(right.Content.RectTransform, "Cost")
    local costBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.32), right.Content.RectTransform), state.itemCost)
    costBox.OnTextChangedDelegate = function(textBox)
        state.itemCost = tostring(textBox.Text or "")
    end

    addText(right.Content.RectTransform, "Reason")
    local reasonBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.32), right.Content.RectTransform), state.itemReason)
    reasonBox.OnTextChangedDelegate = function(textBox)
        state.itemReason = tostring(textBox.Text or "")
    end

    addButton(parent, "ADD SELECTED ITEM TO PURCHASE LIST", function()
        if state.selectedItem ~= nil then
            local cost = trim(state.itemCost) ~= "" and state.itemCost or tostring(itemPrice(state.selectedItem))
            addPurchase(makeItemPurchase(state.selectedItem, state.itemAllocation, state.itemAmount, cost, state.itemReason))
            state.view = "list"
            rebuild()
        else
            setStatus("Select a catalog item before adding it.")
            rebuild()
        end
    end, "Add the selected catalog entry to the manifest.")

    addSection(parent, "QUICK KITS")
    local kitGroup = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.06), parent), true, GUI.Anchor.CenterLeft)

    for _, kit in ipairs(quickKits) do
        local button = GUI.Button(GUI.RectTransform(Vector2(0.333, 1), kitGroup.RectTransform), kit.text, GUI.Alignment.Center, "GUIButtonSmall")
        button.OnClicked = function()
            local added = 0

            for _, itemId in ipairs(kit.ids) do
                local item = findItemById(itemId)
                if item ~= nil then
                    addPurchase(makeItemPurchase(item, kit.allocation, 1, itemPrice(item), kit.reason))
                    added = added + 1
                end
            end

            setStatus("Added " .. tostring(added) .. " entries from " .. tostring(kit.text) .. ".")
            state.view = "list"
            rebuild()
            return true
        end
    end

    addSection(parent, "FOUND BUYABLE ITEMS")
    local resultList = GUI.ListBox(GUI.RectTransform(Vector2(1, 0.36), parent))
    local results = getFilteredItems()
    local limit = math.min(#results, 18)

    if limit == 0 then
        GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.15), resultList.Content.RectTransform), "Nothing found.", nil, nil, GUI.Alignment.Center)
    end

    for i = 1, limit do
        local item = results[i]
        local line = string.format("%s | %s mk | %s", shortText(item.name or item.id, 28), itemPrice(item), shortText(item.soldAt or "unknown", 28))
        local button = GUI.Button(GUI.RectTransform(Vector2(1, 0.095), resultList.Content.RectTransform), line, GUI.Alignment.Left, "GUIButtonSmall")
        paintText(button.TextBlock, palette.text)
        button.ToolTip = "Identifier: " .. tostring(item.id) .. "\nCategory: " .. tostring(item.category) .. "\nTags: " .. tostring(item.tags)
        button.OnClicked = function()
            state.selectedItem = item
            state.itemCost = tostring(itemPrice(item))
            setStatus("Selected " .. tostring(item.name or item.id) .. ".")
            rebuild()
            return true
        end
    end
end

local function drawCrewView(parent, rebuild)
    addSection(parent, "ADD CREW TO HIRE")

    addText(parent, "Name")
    local nameBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.065), parent), state.crewName)
    nameBox.OnTextChangedDelegate = function(textBox)
        state.crewName = tostring(textBox.Text or "")
    end

    addText(parent, "Allocation")
    local allocationBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.065), parent), state.crewAllocation)
    allocationBox.OnTextChangedDelegate = function(textBox)
        state.crewAllocation = tostring(textBox.Text or "")
    end

    addText(parent, "Class / type")
    local typeBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.065), parent), state.crewType)
    typeBox.OnTextChangedDelegate = function(textBox)
        state.crewType = tostring(textBox.Text or "")
    end

    addText(parent, "Amount")
    local amountBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.065), parent), state.crewAmount)
    amountBox.OnTextChangedDelegate = function(textBox)
        state.crewAmount = tostring(textBox.Text or "")
    end

    addText(parent, "Cost")
    local costBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.065), parent), state.crewCost)
    costBox.OnTextChangedDelegate = function(textBox)
        state.crewCost = tostring(textBox.Text or "")
    end

    addText(parent, "Level")
    local levelBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.065), parent), state.crewLevel)
    levelBox.OnTextChangedDelegate = function(textBox)
        state.crewLevel = tostring(textBox.Text or "")
    end

    addButton(parent, "ADD CREW TO PURCHASE LIST", function()
        addPurchase(makeCrewPurchase(state.crewName, state.crewAllocation, state.crewAmount, state.crewCost, state.crewType, state.crewLevel))
        state.crewName = ""
        state.view = "list"
        rebuild()
    end, "Create a crew hire request.")
end

local function drawPurchaseList(parent, rebuild)
    addSection(parent, "PURCHASES / ITEMS AND CREW")

    local searchRow = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.062), parent), true, GUI.Anchor.CenterLeft)
    local searchBox = GUI.TextBox(GUI.RectTransform(Vector2(0.72, 1), searchRow.RectTransform), state.purchaseSearch)
    searchBox.ToolTip = "Search stored purchases by name, allocation, category, reason, crew type or identifier."
    searchBox.OnTextChangedDelegate = function(textBox)
        state.purchaseSearch = tostring(textBox.Text or "")
    end
    searchBox.OnEnterPressed = function()
        setStatus("Manifest search refreshed.")
        rebuild()
        return true
    end

    local searchButton = GUI.Button(GUI.RectTransform(Vector2(0.28, 1), searchRow.RectTransform), "FILTER", GUI.Alignment.Center, "GUIButtonSmall")
    searchButton.OnClicked = function()
        setStatus("Manifest search refreshed.")
        rebuild()
        return true
    end

    local tools = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.06), parent), true, GUI.Anchor.CenterLeft)

    local sortButton = GUI.Button(GUI.RectTransform(Vector2(0.333, 1), tools.RectTransform), "SORT BY COST", GUI.Alignment.Center, "GUIButtonSmall")
    sortButton.OnClicked = function()
        table.sort(SupplyTablet.purchases, function(a, b)
            return purchaseTotal(a) < purchaseTotal(b)
        end)
        state.selectedPurchase = nil
        savePurchases()
        setStatus("Manifest sorted by total cost.")
        rebuild()
        return true
    end

    local clearBoughtButton = GUI.Button(GUI.RectTransform(Vector2(0.333, 1), tools.RectTransform), "CLEAR BOUGHT", GUI.Alignment.Center, "GUIButtonSmall")
    clearBoughtButton.OnClicked = function()
        local kept = {}
        for _, purchase in ipairs(SupplyTablet.purchases) do
            if not purchase.bought then
                table.insert(kept, purchase)
            end
        end
        SupplyTablet.purchases = kept
        state.selectedPurchase = nil
        savePurchases()
        setStatus("Cleared bought entries from the manifest.")
        rebuild()
        return true
    end

    local clearAllButton = GUI.Button(GUI.RectTransform(Vector2(0.333, 1), tools.RectTransform), "CLEAR ALL", GUI.Alignment.Center, "GUIButtonSmall")
    clearAllButton.OnClicked = function()
        SupplyTablet.purchases = {}
        state.selectedPurchase = nil
        savePurchases()
        setStatus("Cleared the manifest.")
        rebuild()
        return true
    end

    local rows = getVisiblePurchases()
    local list = GUI.ListBox(GUI.RectTransform(Vector2(1, 0.39), parent))

    if #rows == 0 then
        GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.16), list.Content.RectTransform), "No purchases stored.", nil, nil, GUI.Alignment.Center)
    end

    for _, row in ipairs(rows) do
        local purchase = row.purchase
        local status = purchase.bought and "BOUGHT" or "OPEN"
        local kind = purchase.type == "crew" and "CREW" or "ITEM"
        local line = string.format("[%s] %s x%s %s | %s mk | %s",
            status,
            kind,
            tostring(purchase.amount),
            shortText(purchase.name, 22),
            tostring(purchaseTotal(purchase)),
            shortText(purchase.allocation, 18))
        local button = GUI.Button(GUI.RectTransform(Vector2(1, 0.085), list.Content.RectTransform), line, GUI.Alignment.Left, "GUIButtonSmall")
        paintText(button.TextBlock, purchase.bought and palette.good or palette.warning)
        button.ToolTip = "Click to edit.\nCost each: " .. tostring(purchase.cost)
        button.OnClicked = function()
            selectPurchase(row.index)
            setStatus("Selected " .. tostring(purchase.name or "purchase") .. " for editing.")
            rebuild()
            return true
        end
    end

    local selected = SupplyTablet.purchases[state.selectedPurchase]

    if selected == nil then
        addText(parent, "Select a purchase to edit, mark bought, or remove.")
        return
    end

    addSection(parent, "EDIT SELECTED PURCHASE")
    addText(parent, "Name")
    local nameBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.055), parent), state.editName)
    nameBox.OnTextChangedDelegate = function(textBox)
        state.editName = tostring(textBox.Text or "")
    end

    addText(parent, "Allocation")
    local allocationBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.055), parent), state.editAllocation)
    allocationBox.OnTextChangedDelegate = function(textBox)
        state.editAllocation = tostring(textBox.Text or "")
    end

    local editGroup = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.075), parent), true, GUI.Anchor.CenterLeft)
    local amountBox = GUI.TextBox(GUI.RectTransform(Vector2(0.5, 1), editGroup.RectTransform), state.editAmount)
    amountBox.ToolTip = "Amount"
    amountBox.OnTextChangedDelegate = function(textBox)
        state.editAmount = tostring(textBox.Text or "")
    end

    local costBox = GUI.TextBox(GUI.RectTransform(Vector2(0.5, 1), editGroup.RectTransform), state.editCost)
    costBox.ToolTip = "Cost"
    costBox.OnTextChangedDelegate = function(textBox)
        state.editCost = tostring(textBox.Text or "")
    end

    if selected.type == "item" then
        addText(parent, "Reason")
        local reasonBox = GUI.TextBox(GUI.RectTransform(Vector2(1, 0.055), parent), state.editReason)
        reasonBox.OnTextChangedDelegate = function(textBox)
            state.editReason = tostring(textBox.Text or "")
        end
    else
        local crewGroup = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.075), parent), true, GUI.Anchor.CenterLeft)
        local crewTypeBox = GUI.TextBox(GUI.RectTransform(Vector2(0.65, 1), crewGroup.RectTransform), state.editCrewType)
        crewTypeBox.ToolTip = "Crew class / type"
        crewTypeBox.OnTextChangedDelegate = function(textBox)
            state.editCrewType = tostring(textBox.Text or "")
        end

        local crewLevelBox = GUI.TextBox(GUI.RectTransform(Vector2(0.35, 1), crewGroup.RectTransform), state.editCrewLevel)
        crewLevelBox.ToolTip = "Level"
        crewLevelBox.OnTextChangedDelegate = function(textBox)
            state.editCrewLevel = tostring(textBox.Text or "")
        end
    end

    local actionGroup = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.065), parent), true, GUI.Anchor.CenterLeft)

    local applyButton = GUI.Button(GUI.RectTransform(Vector2(0.25, 1), actionGroup.RectTransform), "APPLY", GUI.Alignment.Center, "GUIButtonSmall")
    applyButton.OnClicked = function()
        applySelectedEdit()
        rebuild()
        return true
    end

    local boughtButton = GUI.Button(GUI.RectTransform(Vector2(0.25, 1), actionGroup.RectTransform), selected.bought and "NOT BOUGHT" or "BOUGHT", GUI.Alignment.Center, "GUIButtonSmall")
    boughtButton.OnClicked = function()
        selected.bought = not selected.bought
        savePurchases()
        setStatus(tostring(selected.name or "Purchase") .. (selected.bought and " marked bought." or " marked open."))
        rebuild()
        return true
    end

    local plusButton = GUI.Button(GUI.RectTransform(Vector2(0.25, 1), actionGroup.RectTransform), "+1", GUI.Alignment.Center, "GUIButtonSmall")
    plusButton.OnClicked = function()
        selected.amount = parsePositiveInt(selected.amount, 1) + 1
        selectPurchase(state.selectedPurchase)
        savePurchases()
        setStatus("Increased amount for " .. tostring(selected.name or "purchase") .. ".")
        rebuild()
        return true
    end

    local removeButton = GUI.Button(GUI.RectTransform(Vector2(0.25, 1), actionGroup.RectTransform), "REMOVE", GUI.Alignment.Center, "GUIButtonSmall")
    removeButton.OnClicked = function()
        removePurchase(state.selectedPurchase)
        rebuild()
        return true
    end
end

local function drawReports(parent)
    local data = summary()

    addSection(parent, "REPORTS AND FILTERS")
    addText(parent, "Total purchases: " .. tostring(#SupplyTablet.purchases))
    addStatusText(parent, "Total cost: " .. tostring(data.total) .. " mk", palette.money)
    addStatusText(parent, "Not bought: " .. tostring(data.notBoughtCount) .. " | " .. tostring(data.notBoughtTotal) .. " mk", palette.warning)
    addStatusText(parent, "Bought: " .. tostring(data.boughtCount) .. " | " .. tostring(data.boughtTotal) .. " mk", palette.good)
    addText(parent, "Items: " .. tostring(data.itemCount) .. " | Crew: " .. tostring(data.crewCount))

    addSection(parent, "CATEGORY SUMMARY")
    local list = GUI.ListBox(GUI.RectTransform(Vector2(1, 0.5), parent))
    local categories = categorySummary()

    if #categories == 0 then
        GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.15), list.Content.RectTransform), "No item categories stored.", nil, nil, GUI.Alignment.Center)
    end

    for _, row in ipairs(categories) do
        local line = shortText(row.category, 34) .. ": " .. tostring(row.count) .. " purchases, " .. tostring(row.total) .. " mk"
        paintText(GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.09), list.Content.RectTransform), line, nil, nil, GUI.Alignment.Left), palette.text)
    end
end

local function createTabletUi(instance)
    local frame = instance.GuiFrame

    if frame == nil then
        print("[Supply Tablet] CustomInterface has no GuiFrame yet.")
        return
    end

    print("[Supply Tablet] Drawing tablet interface.")

    local rebuild

    rebuild = function()
        frame.ClearChildren()

        local mainList = GUI.ListBox(GUI.RectTransform(Vector2(1, 1), frame.RectTransform, GUI.Anchor.Center))
        local data = summary()

        addTitle(mainList.Content.RectTransform, "BAROTRAUMA SUPPLY TABLET")
        addStatusText(mainList.Content.RectTransform, "Open: " .. tostring(data.notBoughtCount) .. " | Bought: " .. tostring(data.boughtCount) .. " | Needed budget: " .. tostring(data.notBoughtTotal) .. " mk", palette.money)
        addStatusText(mainList.Content.RectTransform, tostring(state.lastStatus), palette.dim)
        addTabButtons(mainList.Content.RectTransform, rebuild)

        if state.view == "intro" then
            drawIntro(mainList.Content.RectTransform, rebuild)
        elseif state.view == "items" then
            drawItemView(mainList.Content.RectTransform, rebuild)
        elseif state.view == "crew" then
            drawCrewView(mainList.Content.RectTransform, rebuild)
        elseif state.view == "list" then
            drawPurchaseList(mainList.Content.RectTransform, rebuild)
        else
            drawReports(mainList.Content.RectTransform)
        end
    end

    rebuild()
end

local function identifierToString(identifier)
    if identifier == nil then
        return ""
    end

    local okValue, value = pcall(function()
        return tostring(identifier.Value)
    end)

    if okValue and value ~= nil and value ~= "" then
        return value:lower()
    end

    return tostring(identifier):lower()
end

local function isSupplyTabletInterface(instance)
    local okElement, originalElement = pcall(function()
        return instance.originalElement
    end)

    if okElement and originalElement ~= nil then
        local okType, interfaceType = pcall(function()
            return originalElement.GetAttributeString("type", "")
        end)

        if okType and tostring(interfaceType) == "supplytablet" then
            return true
        end
    end

    local okItem, item = pcall(function()
        return instance.Item or instance.item
    end)

    if not okItem or item == nil then
        okItem, item = pcall(function()
            return instance.item
        end)
    end

    if okItem and item ~= nil then
        local okIdentifier, identifier = pcall(function()
            return item.Prefab.Identifier
        end)

        if okIdentifier and identifierToString(identifier) == "supplytablet" then
            return true
        end
    end

    return false
end

loadPurchases()

if SupplyTablet.hookInstalled then
    return
end

SupplyTablet.hookInstalled = true

Hook.Patch("SupplyTablet.CustomInterface.CreateGUI", "Barotrauma.Items.Components.CustomInterface", "CreateGUI", function(instance, _)
    if instance == nil then
        return
    end

    if not isSupplyTabletInterface(instance) then
        return
    end

    createTabletUi(instance)
end, Hook.HookMethodType.After)

print("[Supply Tablet] Loaded full in-game purchase system with " .. tostring(#SupplyTabletCatalog) .. " buyable catalog items.")
