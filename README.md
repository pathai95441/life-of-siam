# Siam Life

เกม 2D top-down life simulation ในบรรยากาศไทย สร้างด้วย **Godot 4.7.2** (GDScript)

---

## เปิดโปรเจกต์

1. ติดตั้ง Godot 4.7.2 — `brew install --cask godot` หรือ https://godotengine.org/download/macos/
2. เปิด Godot → **Import** → เลือกไฟล์ `project.godot` ในโฟลเดอร์นี้
3. ครั้งแรกที่เปิด Godot จะสร้าง `.godot/` เอง (ถูก gitignore ไว้)
4. กด **F5** เพื่อรัน — จะเข้าหน้า Main Menu

โปรเจกต์นี้ compile ผ่านและบูตสะอาดบน Godot 4.7.2 แล้ว (ไม่มี error, ไม่มี warning)

## รันเทสต์

```bash
godot --headless --path . tests/smoke_test.tscn
```

ครอบ core loop 50 ข้อ: นาฬิกา/ฤดู, กระเป๋าล้น, พลิกดิน-ปลูก-รดน้ำ-โต-เหี่ยว-เก็บเกี่ยว,
save round trip ผ่าน JSON จริง, การกันปลูกผิดฤดู, บทสนทนา, และเศรษฐกิจ
exit code ไม่ใช่ 0 เมื่อมีข้อตก — ใช้เป็น CI gate ได้ทันที

## ปุ่มควบคุม

| ปุ่ม | ทำอะไร |
|---|---|
| `W A S D` / ลูกศร | เดิน |
| `Shift` (กดค้าง) | วิ่ง (กินสตามินา) |
| `E` / `Space` | คุย / ใช้งานสิ่งของรอบตัว |
| คลิกซ้าย | ใช้ของในมือกับช่องดินข้างหน้า |
| `1`–`5` | เลือกช่อง hotbar |
| `I` / `Tab` | เปิด-ปิดกระเป๋า |
| `Esc` | หยุดเกม |
| `F5` | quick save (ช่อง 0) |

## ลูปการเล่นที่เล่นได้แล้ว

จอบพลิกดิน → หยอดเมล็ด → รดน้ำ → นอน (เตียงมุมซ้ายบน) → วันใหม่ พืชโต → เก็บเกี่ยวด้วยมือเปล่าหรือเคียว → ของเข้ากระเป๋า → เกมเซฟอัตโนมัติตอนนอน

คุยกับ **สมชาย** เพื่อทดสอบระบบบทสนทนา อ่านป้ายเพื่อดูวิธีเล่น

## โครงสร้างโฟลเดอร์

```
assets/      งานศิลป์และเสียง (ยังว่าง — ตอนนี้ใช้ debug draw แทน)
resources/   ไฟล์ .tres ที่ออกแบบไว้ (items, crops, npcs, dialogue)
src/
  autoload/  ระบบกลาง 10 ตัว (singleton)
  core/      ค่าคงที่และ enum
  data/      คลาส Resource สำหรับข้อมูลเกม
  components/ ชิ้นส่วนที่นำไปประกอบซ้ำได้ (FSM, interactable, tool handler)
  entities/  player, npc, props
  systems/   farming, interaction, inventory slot
  ui/        hud, menus, dialogue, inventory
  world/     ฉากแผนที่
tests/       ยังว่าง — ดู "Missing systems" ในเอกสารสถาปัตยกรรม
docs/        เอกสารสถาปัตยกรรม
```

## เอกสาร

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — สถาปัตยกรรม, dependency graph, technical debt, ความเสี่ยง, ลำดับงานที่แนะนำ
