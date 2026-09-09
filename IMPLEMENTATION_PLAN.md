# IMPLEMENTATION_PLAN.md

แผนเดิม 5 เฟสอยู่ใน `docs/ARCHITECTURE.md` §7 — **ไฟล์นี้ไม่ลบแผนเดิม** แต่แทรก
เฟส 2.5D เข้ามาก่อนเฟส 1 เพราะทิศทางภาพเปลี่ยน (ดูเหตุผลใน "ทำไมต้องแทรก")

## สถานะเฟส

| เฟส | ชื่อ | สถานะ |
|---|---|---|
| 0 | ทำให้รันจริง | 🟡 4/5 — เหลือกด F5 เล่นด้วยมือ |
| **W** | **World-object model (2.5D foundation)** | 🔵 **กำลังทำ** |
| 1 | Theme + ฟอนต์ไทย + เทสต์ | ⬜ รอ |
| 2 | ปิดลูปเศรษฐกิจ (shipping bin, shop) | ⬜ รอ |
| 3 | ขยายโลก (แผนที่ที่ 2, NPC schedule) | ⬜ รอ |
| 4 | ทำให้ดูเป็นเกม (TileSet, animation, เสียง) | ⬜ รอ |
| 5 | ปล่อยได้ (save slot UI, localisation, CI) | ⬜ รอ |

### ทำไมต้องแทรกเฟส W ก่อนเฟส 1

ทิศทางเปลี่ยนเป็น 2.5D แล้ว ขนาดในเกมทุกตัวตอนนี้เป็น magic number ที่จิ้มมือใน
`.tscn` 8 จุด ถ้าเพิ่ม entity ต่อไปก่อนวาง spatial model จะต้อง **เขียน entity scene
ใหม่สองรอบ** — รอบแรกตามขนาดที่จิ้มไว้ รอบสองตอนย้ายมาใช้ data model
ต้นทุนของการเลื่อนเฟสนี้จึงโตตามจำนวน entity ที่เพิ่มระหว่างรอ

---

# PHASE W — World-object model (2.5D foundation)

## PHASE OBJECTIVE

ให้ทุก world object มีขนาดที่มาจาก **Resource เดียว** และแยก 4 ขอบเขตออกจากกัน
(logical footprint / collision / interaction / visual) พร้อมคณิตศาสตร์โปรเจกชัน
2.5D ที่ทดสอบได้โดยไม่ต้องเรนเดอร์

**ไม่อยู่ในขอบเขตเฟสนี้:** art จริง, isometric tileset, animation, ระบบใหม่ใด ๆ
เฟสนี้คือการเปลี่ยนวิธี "รู้ขนาด" ไม่ใช่การเพิ่ม feature

## DEPENDENCIES

| ต้องมีก่อน | สถานะ |
|---|---|
| `GAME_DESIGN.md` §2 canonical scale ที่พี่ยืนยันแล้ว | ⛔ **ยังไม่ยืนยัน — บล็อกอยู่** |
| ตัดสินใจโปรเจกชัน (oblique vs isometric) | ⛔ ยังไม่ตัดสินใจ |
| `GameConstants.TILE_SIZE` | ✅ มี |
| `Interactable` + `InteractionProbe` | ✅ มี — จะ refactor ไม่เขียนใหม่ |
| `smoke_test` เป็น regression baseline | ✅ มี 50/50 |

## ARCHITECTURAL IMPACT

**เพิ่มชั้นใหม่ 1 ชั้น** ระหว่าง `core` กับ `entities`

```
core/       GameConstants (เดิม)
            world_space.gd        ← ใหม่: คณิตศาสตร์ล้วน static ไม่มี node
data/       world_object_data.gd  ← ใหม่: Resource กำหนด footprint/height/origin
components/ world_body.gd         ← ใหม่: อ่าน Resource แล้วสร้าง shape ให้เอง
entities/   player/npc/props      ← refactor ให้ใช้ world_body
```

**dependency ทิศทาง:** `world_space` ไม่พึ่งใครเลย (pure static) → `world_object_data`
พึ่ง `world_space` → `world_body` พึ่งทั้งสอง → entity พึ่ง `world_body`
ไม่มี cycle และ `world_space` ทดสอบได้โดยไม่ต้องมี SceneTree

**ระบบที่กระทบ:** `FarmGrid.world_to_cell/cell_to_world` ต้องเปลี่ยนไปเรียก
`WorldSpace` แทนการหาร `TILE_SIZE` เอง · `InteractionProbe` ต้องใช้ interaction
bounds จาก data แทน shape ที่จิ้มไว้ · `world.tscn` ต้องเรียง depth ด้วย world y

## TASK BREAKDOWN

| Task | ทำอะไร | ผลที่ทดสอบได้ |
|---|---|---|
| **W1** | `core/world_space.gd` — โปรเจกชัน world↔screen, footprint rect, depth key ทั้งหมดเป็น static | unit test ล้วน ไม่ต้องเรนเดอร์: round-trip world→screen→world, ลำดับ depth ถูกต้อง |
| **W2** | `data/world_object_data.gd` — Resource: footprint, height, origin, blocks_movement, interaction_reach + `.tres` ตามตาราง scale | โหลด `.tres` ผ่าน `Database` ได้, ค่าตรงตาราง, validation จับค่าติดลบ |
| **W3** | `components/world_body.gd` — สร้าง collision + interaction shape จาก data ตอน `_ready` | เทียบ shape ที่สร้างกับค่าที่คำนวณจาก data, ยืนยันว่าไม่มี shape ใน `.tscn` เหลือ |
| **W4** | ย้าย `Player` มาใช้ `world_body` ลบ shape ที่ hardcode | smoke test ยังผ่าน 50/50 + เทสต์ใหม่ว่า footprint ผู้เล่นตรง data |
| **W5** | ย้าย `Npc` / `Bed` / `SignPost` มาใช้ `world_body` | ยัง interact ได้ทุกตัว, ไม่มี magic number เหลือใน entity `.tscn` |
| **W6** | `FarmGrid` เรียก `WorldSpace` แทนการหาร `TILE_SIZE` เอง | cell math ให้ผลเดิมเป๊ะ (regression) + รองรับ depth ratio |
| **W7** | depth sorting ด้วย world y ใน `world.tscn` | เทสต์ฉากเล็ก: วางวัตถุ 3 ชิ้นต่างระยะ ยืนยันลำดับการวาด |
| **W8** | ซอย `smoke_test.gd` (125 บรรทัด → หลายไฟล์) ตามกฎ ≤40 บรรทัด/ฟังก์ชัน | เทสต์ทั้งหมดยังผ่าน จำนวน assertion ไม่ลด |

## TASK ORDER

`W1 → W2 → W3 → W4 → W5 → W6 → W7`  ·  `W8` แทรกได้ตอนไหนก็ได้ (ไม่มี dependency)

เหตุผล: W1 เป็นคณิตศาสตร์ล้วนที่ทุกอย่างพึ่ง ต้องถูกก่อน · W2 คือ data ที่ W3 อ่าน ·
W4 ทำ Player ก่อน entity อื่นเพราะมันคือตัวที่ regression เห็นชัดที่สุด · W6/W7 ทำท้าย
เพราะเป็นการเปลี่ยนระบบที่ทำงานอยู่แล้ว ความเสี่ยงสูงสุด

## TEST STRATEGY

| ชั้น | ใช้กับ | วิธี |
|---|---|---|
| **Unit** (ไม่ต้องเรนเดอร์) | `WorldSpace`, `WorldObjectData` validation | เรียก static function ตรง ๆ เทียบค่าที่คำนวณมือ |
| **Integration** | `WorldBody` สร้าง shape, `FarmGrid` cell math | ฉากเทสต์เล็ก instance node จริงแล้วอ่าน shape กลับมาเทียบ |
| **Regression** | ทุก task | `smoke_test` เดิมต้องผ่าน 50/50 ทุกครั้ง ห้ามลดจำนวน assertion |
| **Manual visual** | W7 depth sorting | กด F5 ดูด้วยตา — headless ตรวจลำดับการวาดจริงไม่ได้ |

**ทุก task ต้องตอบ 4 ข้อ:** ทดสอบอะไร / ทดสอบยังไง / ผลที่คาด / เงื่อนไขที่ถือว่าพัง

## DEFINITION OF DONE (ทั้งเฟส)

1. `grep -rn "RectangleShape2D\|CircleShape2D" src/entities` **ไม่เจอ shape ที่ hardcode**
2. ขนาดทุกอย่างมาจาก `.tres` แก้ตัวเลขในไฟล์เดียวแล้วเกมเปลี่ยนตาม
3. `godot --headless --path . --editor --quit` ไม่มี SCRIPT ERROR
4. `smoke_test` ผ่าน 50/50 (assertion ไม่ลด) + เทสต์ใหม่ของเฟส W ผ่านทั้งหมด
5. ไม่มีไฟล์ > 250 บรรทัด ไม่มีฟังก์ชัน > 40 บรรทัด
6. `docs/ARCHITECTURE.md` อัปเดตชั้นใหม่และ dependency graph
7. กด F5 แล้วเห็นการเรียงหน้า-หลังถูกต้องด้วยตา

## RISKS

| ระดับ | ความเสี่ยง | ลดอย่างไร |
|---|---|---|
| 🔴 | **ยังไม่ยืนยัน canonical scale** — ถ้าตารางใน `GAME_DESIGN.md` เปลี่ยนหลังผมทำ W2–W5 ต้องรื้อ `.tres` ทั้งหมด | **บล็อกเฟสไว้จนพี่ยืนยันตาราง** ค่าตัวเลขอยู่ที่เดียวเพื่อให้แก้ครั้งเดียวจบ |
| 🔴 | **โปรเจกชันยังไม่ตัดสินใจ** — isometric กับ oblique ให้คณิตศาสตร์ W1 ต่างกันคนละเรื่อง | บล็อกเช่นกัน · W1 ออกแบบให้สลับสูตรได้ที่จุดเดียว |
| 🟠 | refactor `FarmGrid`/`InteractionProbe` ที่ทำงานอยู่แล้วอาจพัง | `smoke_test` เป็น baseline · W6 อยู่ท้ายสุด · ทำ task ละ commit |
| 🟠 | y_sort ของ Godot เรียงด้วย screen y ไม่ใช่ world y — พอมี depth ratio อาจเรียงผิด | W7 มีเทสต์ฉากเฉพาะ + ต้องยืนยันด้วยตา |
| 🟡 | over-engineering — สร้าง abstraction เกินที่เกมต้องใช้ | ยึดกฎ: ทำแค่ที่ 8 magic number ปัจจุบันต้องใช้ ไม่เพิ่ม field เผื่ออนาคต |

---

## DISCOVERED TASKS

พบระหว่างตรวจโปรเจกต์ตามกฎใหม่ ยังไม่จัดเข้าเฟส

| # | งาน | กฎที่ผิด | เสนอทำที่ |
|---|---|---|---|
| D1 | `smoke_test.gd::_ready` ยาว 125 บรรทัด | ฟังก์ชัน ≤ 40 | = Task W8 |
| D2 | `scene_loader.gd::change_scene` 49 บรรทัด | ฟังก์ชัน ≤ 40 | เฟส 1 |
| D3 | collision magic number 8 จุด | no magic numbers | = Task W3–W5 |
| D4 | ธง `talked_<npc>_day_<n>` สะสมไม่มีขอบเขต ทำไฟล์เซฟบวม | หนี้ #6 เดิม | เฟส 1 (ก่อนเพิ่ม NPC) |
| D5 | ไม่มี `AGENTS.md` / `IMPLEMENTATION_PLAN.md` | — | ✅ เสร็จแล้ว |
