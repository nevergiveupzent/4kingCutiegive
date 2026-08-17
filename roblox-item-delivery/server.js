/**
 * server.js
 * เว็บ backend สำหรับสั่งให้ไอเทมกับผู้เล่นใน Roblox แบบ real-time
 * ผ่าน Roblox Open Cloud - MessagingService Publish API
 *
 * วิธีใช้:
 * 1. npm init -y && npm install express node-fetch dotenv
 * 2. สร้างไฟล์ .env ตามตัวอย่างด้านล่าง
 * 3. node server.js
 */

require("dotenv").config();
const express = require("express");
const fetch = require("node-fetch");

const app = express();
app.use(express.json());

// ====== ตั้งค่าจาก .env ======
// UNIVERSE_ID       = Universe ID ของเกม (หาได้จาก Creator Dashboard)
// ROBLOX_API_KEY    = API Key จาก Open Cloud (ต้องมีสิทธิ์ MessagingService:Publish)
// ADMIN_SECRET      = รหัสลับที่เว็บของคุณเองใช้ยืนยันว่าคำขอนี้ถูกต้อง (กันคนอื่นยิง endpoint นี้มั่ว)
const { UNIVERSE_ID, ROBLOX_API_KEY, ADMIN_SECRET, DISCORD_WEBHOOK_URL } = process.env;
const TOPIC = "GiveItem"; // ต้องตรงกับ topic ที่ฝั่ง Roblox subscribe ไว้

// ส่ง log เข้า Discord webhook (ไม่ทำให้ request หลักพังถ้า Discord ล่ม)
async function logToDiscord(payload, status) {
  if (!DISCORD_WEBHOOK_URL) return;
  const color = status === "sent" ? 0x3498db : 0xe74c3c; // ฟ้า = ส่งสำเร็จ, แดง = ผิดพลาด
  try {
    await fetch(DISCORD_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        embeds: [
          {
            title: status === "sent" ? "📤 ส่งคำสั่งให้ไอเทม" : "❌ ส่งคำสั่งไม่สำเร็จ",
            color,
            fields: [
              { name: "userId", value: String(payload.userId), inline: true },
              { name: "item", value: String(payload.itemId), inline: true },
              { name: "amount", value: String(payload.amount), inline: true },
              { name: "requestId", value: String(payload.requestId), inline: false },
            ],
            timestamp: new Date().toISOString(),
          },
        ],
      }),
    });
  } catch (err) {
    console.error("ส่ง Discord log ไม่สำเร็จ:", err.message);
  }
}

/**
 * POST /give-item
 * body: { "secret": "...", "userId": 123456, "itemId": "sword_01", "amount": 1 }
 */
app.post("/give-item", async (req, res) => {
  const { secret, userId, itemId, amount } = req.body;

  // 1) ตรวจสอบสิทธิ์ผู้ยิง request (เว็บของคุณเอง / ระบบซื้อขาย ฯลฯ)
  if (secret !== ADMIN_SECRET) {
    return res.status(401).json({ error: "unauthorized" });
  }
  if (!userId || !itemId) {
    return res.status(400).json({ error: "missing userId or itemId" });
  }

  const payload = {
    userId: Number(userId),
    itemId: String(itemId),
    amount: Number(amount) || 1,
    requestId: `${Date.now()}-${Math.random().toString(36).slice(2)}`, // กันซ้ำ
  };

  try {
    const response = await fetch(
      `https://apis.roblox.com/messaging-service/v1/universes/${UNIVERSE_ID}/topics/${TOPIC}`,
      {
        method: "POST",
        headers: {
          "x-api-key": ROBLOX_API_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ message: JSON.stringify(payload) }),
      }
    );

    if (!response.ok) {
      const errText = await response.text();
      console.error("Roblox API error:", response.status, errText);
      await logToDiscord(payload, "failed");
      return res.status(502).json({ error: "roblox_publish_failed", detail: errText });
    }

    console.log("ส่งคำสั่งให้ไอเทมสำเร็จ:", payload);
    await logToDiscord(payload, "sent");
    res.json({ ok: true, payload });
  } catch (err) {
    console.error(err);
    await logToDiscord(payload, "failed");
    res.status(500).json({ error: "server_error" });
  }
});

app.listen(3000, () => console.log("Server running on port 3000"));
