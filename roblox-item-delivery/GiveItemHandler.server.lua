--[[
    GiveItemHandler.server.lua
    วางไว้ใน ServerScriptService

    ก่อนใช้งาน:
    1) เปิด Game Settings > Security > Allow HTTP Requests = true
    2) แก้ DISCORD_WEBHOOK_URL ด้านล่างเป็น webhook URL ของคุณ
    3) itemId ที่ส่งมาจากเว็บ ต้องตรงกับชื่อ stat ใน leaderstats เป๊ะๆ
       เช่น leaderstats มี "Coins" -> ส่ง itemId = "Coins"
--]]

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local TOPIC = "GiveItem"
local DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/XXXXXXXX/XXXXXXXXXXXXXXXX" -- แก้ตรงนี้
local PendingItemsStore = DataStoreService:GetDataStore("PendingItems_v1")

-- ============ ส่ง log เข้า Discord ============
local function logToDiscord(title, color, fields)
    if DISCORD_WEBHOOK_URL == "" then return end
    local embed = {
        title = title,
        color = color,
        fields = fields,
        timestamp = DateTime.now():ToIsoDate(),
    }
    local body = HttpService:JSONEncode({ embeds = { embed } })

    local ok, err = pcall(function()
        HttpService:PostAsync(DISCORD_WEBHOOK_URL, body, Enum.HttpContentType.ApplicationJson)
    end)
    if not ok then
        warn("ส่ง Discord log ไม่สำเร็จ:", err)
    end
end

-- ============ ให้ไอเทมผ่าน leaderstats ============
-- itemId ต้องตรงกับชื่อ stat ใน leaderstats เช่น "Coins", "Gems"
local function giveItemToPlayer(player, itemId, amount)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then
        warn("ไม่พบ leaderstats ของ " .. player.Name)
        logToDiscord("❌ ให้ไอเทมไม่สำเร็จ (ไม่มี leaderstats)", 0xe74c3c, {
            { name = "player", value = player.Name, inline = true },
            { name = "item", value = itemId, inline = true },
        })
        return false
    end

    local stat = leaderstats:FindFirstChild(itemId)
    if not stat then
        warn(("ไม่พบ stat '%s' ใน leaderstats ของ %s"):format(itemId, player.Name))
        logToDiscord("❌ ให้ไอเทมไม่สำเร็จ (ไม่พบ stat)", 0xe74c3c, {
            { name = "player", value = player.Name, inline = true },
            { name = "item", value = itemId, inline = true },
        })
        return false
    end

    stat.Value += amount

    print(("มอบ %s x%d ให้กับ %s (คงเหลือ %s)"):format(itemId, amount, player.Name, tostring(stat.Value)))
    logToDiscord("✅ ให้ไอเทมสำเร็จ", 0x2ecc71, {
        { name = "player", value = player.Name, inline = true },
        { name = "item", value = itemId, inline = true },
        { name = "amount", value = tostring(amount), inline = true },
        { name = "new_total", value = tostring(stat.Value), inline = true },
    })
    return true
end

-- ============ รอ leaderstats โหลดเสร็จก่อน (กันเคส stat ยังไม่ถูกสร้าง) ============
local function waitForLeaderstats(player, timeoutSec)
    timeoutSec = timeoutSec or 10
    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats then return leaderstats end

    local start = os.clock()
    while os.clock() - start < timeoutSec do
        leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats then return leaderstats end
        task.wait(0.5)
    end
    return nil
end

-- ============ เก็บคำสั่งค้างไว้เผื่อผู้เล่น offline ============
local function queuePendingItem(userId, itemId, amount)
    local key = "user_" .. tostring(userId)
    local ok, err = pcall(function()
        PendingItemsStore:UpdateAsync(key, function(old)
            old = old or {}
            table.insert(old, { itemId = itemId, amount = amount })
            return old
        end)
    end)
    if not ok then
        warn("บันทึกคำสั่งค้างไม่สำเร็จ:", err)
    else
        logToDiscord("📥 เก็บคำสั่งไว้รอ (ผู้เล่นออฟไลน์)", 0xf39c12, {
            { name = "userId", value = tostring(userId), inline = true },
            { name = "item", value = itemId, inline = true },
            { name = "amount", value = tostring(amount), inline = true },
        })
    end
end

-- ============ รับ message แบบ real-time จากเว็บ ============
MessagingService:SubscribeAsync(TOPIC, function(message)
    local ok, data = pcall(function()
        return HttpService:JSONDecode(message.Data)
    end)
    if not ok or not data then
        warn("ข้อมูลที่ได้รับผิดรูปแบบ")
        return
    end

    local userId = data.userId
    local itemId = data.itemId
    local amount = data.amount or 1

    local player = Players:GetPlayerByUserId(userId)
    if player then
        giveItemToPlayer(player, itemId, amount)
    else
        queuePendingItem(userId, itemId, amount)
    end
end)

-- ============ เช็คคำสั่งค้างตอนผู้เล่นเข้าเกม ============
Players.PlayerAdded:Connect(function(player)
    local leaderstats = waitForLeaderstats(player, 10)
    if not leaderstats then
        warn("รอ leaderstats ของ " .. player.Name .. " นานเกินไป ยกเลิกการเช็คคำสั่งค้าง")
        return
    end

    local key = "user_" .. tostring(player.UserId)
    local ok, pending = pcall(function()
        return PendingItemsStore:GetAsync(key)
    end)

    if ok and pending then
        for _, item in ipairs(pending) do
            giveItemToPlayer(player, item.itemId, item.amount)
        end
        pcall(function()
            PendingItemsStore:RemoveAsync(key)
        end)
    end
end)
