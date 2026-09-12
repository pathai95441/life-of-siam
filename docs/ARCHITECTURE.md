# Siam Life — สถาปัตยกรรม

เอกสารนี้คือรายงาน 7 หัวข้อที่ตกลงกันไว้ เขียนจากโค้ดที่มีอยู่จริงในโปรเจกต์นี้
ปรับปรุงเมื่อโครงสร้างเปลี่ยน — ถ้าเอกสารกับโค้ดไม่ตรงกัน ให้ถือว่าเอกสารผิด

---

## 1. สถาปัตยกรรมปัจจุบัน

แบ่ง 4 ชั้น กฎคือ **ชั้นล่างไม่รู้จักชั้นบน**

```
ชั้นที่ 5  VIEW        HUD, DialogueBox, InventoryPanel, Menus
                       อ่านสถานะ + ฟัง EventBus เท่านั้น ห้ามเขียนสถานะเกม
                                    ▲ (signal)
ชั้นที่ 4  ENTITY      Player (FSM), Npc, Bed, SignPost
                       ตัวตนในฉาก ประกอบจาก component · ไม่ถือขนาดเอง
                                    ▲
ชั้นที่ 3  SYSTEM      FarmGrid, InteractionProbe, ToolHandler, StateMachine
                       ตรรกะเกมที่จับต้องฉากได้
                                    ▲
ชั้นที่ 2  SPATIAL     WorldSpace (static, โปรเจกชัน oblique 3/4)
                       WorldObjectData (Resource: footprint/height/origin)
                       WorldBody, PlaceholderVisual (component)
                       แหล่งความจริงเดียวเรื่อง "ขนาด" และ "พื้นที่"
                                    ▲
ชั้นที่ 1  GLOBAL      autoload 10 ตัว — สถานะที่ต้องอยู่ข้ามฉาก
                       EventBus, SettingsManager, Database, AudioManager,
                       SaveManager, GameClock, GameState, Inventory,
                       DialogueSystem, SceneLoader
```

### หลักการที่ใช้ตัดสินใจ

**ขนาดมาจาก Resource ไม่ใช่จาก sprite และไม่ใช่จาก `.tscn`**
`WorldObjectData` เป็นเจ้าของ footprint/height/origin · `WorldSpace` เป็นที่เดียว
ที่แปลง world↔screen · `WorldBody` สร้าง collision/interaction shape ตอน runtime
ไม่มี `.tscn` ไหนใน `src/entities/` ถือ shape อีกแล้ว (ยืนยันด้วย grep ใน DoD)

แยก 4 ขอบเขตชัดเจน: **logical footprint** (กฎเกมใช้อันนี้) · **collision** ·
**interaction** · **visual** (เป็นของ sprite ห้ามย้อนกลับมาป้อนกฎ)

**Model แยกจาก View เด็ดขาด**
`FarmGrid` เก็บสถานะดินทุกช่องใน `Dictionary[Vector2i, SoilCell]` แล้ววาดด้วย
`_draw()` แบบ debug ไว้ก่อน — เปลี่ยนไปใช้ TileMapLayer + Sprite pool ทีหลังโดย
**ไม่ต้องแก้ไฟล์อื่นเลย** นี่คือเหตุผลที่ยอมเขียน `_draw()` ทิ้งไว้

**EventBus เป็นทางเดียวสำหรับการคุยข้ามระบบ**
ระบบที่ไม่รู้จักกันคุยผ่าน bus, node กับลูกของตัวเองใช้ signal ตรง
ผู้ส่งไม่เคยสมมติว่ามีคนฟัง ผู้ฟังไม่เคยสมมติลำดับ

**สถานะกระจายตามเจ้าของ ไม่รวมกองเดียว**
- เวลา → `GameClock` เท่านั้น
- ของในกระเป๋า → `Inventory` เท่านั้น
- เงิน/ธง/ความสัมพันธ์ → `GameState`
- ดินและพืช → `FarmGrid` (ในฉาก)

ไม่มี "GameManager" ที่ถือทุกอย่าง เพราะนั่นคือจุดที่โปรเจกต์เกมมักพัง

**FSM แทน boolean flags**
สถานะผู้เล่นเป็น node ลูกจริง ๆ (`Idle`, `Walk`, `UseTool`, `Locked`)
`Locked` มีอยู่เพื่อไม่ให้สถานะอื่นต้องเขียน `if not is_talking` กระจัดกระจาย

**Save เป็น JSON ไม่ใช่ binary**
เซฟที่อ่านด้วย text editor ได้ = เซฟที่ debug และแก้มือได้
ทุกไฟล์มี `save_version` เพื่อ migrate ตอนอัปเดต

### สัญญา save (duck-typed)

node ที่จะถูกเซฟต้องมี 3 เมธอด และอยู่ใน group ใด group หนึ่ง:

```gdscript
func get_save_id() -> StringName
func save_state() -> Dictionary
func load_state(data: Dictionary) -> void
```

| group | ใครอยู่ | ฟื้นตอนไหน |
|---|---|---|
| `save_provider` | autoload ที่อยู่ตลอด (GameClock, GameState, Inventory) | ทันทีที่โหลด — ก่อนสร้างฉาก |
| `saveable` | node ที่เป็น**ของแผนที่** (FarmGrid, ShippingBin) | ทุกครั้งที่เข้าแผนที่นั้น |
| `traveller` | node ที่**เดินข้ามแผนที่** (Player) | **เฉพาะแผนที่แรกหลังโหลดเซฟ** — ประตูใช้ spawn เสมอ |

**ทำไม `traveller` ต้องแยก:** ถ้าผู้เล่นถูกเก็บเป็นของแผนที่ การเดินกลับเข้าแผนที่เดิม
จะคืนตำแหน่งที่เคยยืนทับจุดที่ประตูพามา — โหลดเซฟกับเดินผ่านประตูเป็นคนละเรื่อง

**สถานะแผนที่อยู่ตลอดเซสชัน ไม่ใช่ใช้แล้วทิ้ง** — เก็บตอนออกจากแผนที่
(`scene_change_started` คือจังหวะสุดท้ายที่ฉากเก่ายังอ่านได้) คืนตอนเข้า
ถ้าทิ้งหลังใช้ครั้งเดียว เดินออกแล้วกลับมาไร่จะว่างเปล่าโดยไม่มี error ใด ๆ

เจตนา: `SaveManager` เป็นผู้ประสานงาน **ไม่ถือข้อมูลเกมเอง** เพิ่มระบบใหม่ =
เพิ่ม 3 เมธอด + `add_to_group()` ไม่ต้องแก้ `SaveManager` เลย

### ทำไมต้องใช้ group ไม่ใช้ registry

`GameClock._ready()` รันก่อน `SaveManager` จะถูกสร้าง (ลำดับ autoload)
ถ้าใช้ `SaveManager.register_provider()` จะพังทันที การใช้ group ทำให้
**ลำดับ autoload ไม่มีผล** — เป็นข้อผิดพลาดที่ถูกพบและแก้ระหว่างสร้างโครงนี้

---

## 2. Dependency graph

```
                    ┌──────────┐
                    │ EventBus │  ◄── ทุกคนยิงเข้า/ฟังจากที่นี่
                    └──────────┘      ตัวมันเองไม่พึ่งใครเลย

GameConstants ◄──── (ทุกไฟล์)        pure consts, ไม่พึ่งใคร

Database ◄──── ItemData, CropData, NpcData, DialogueData
   ▲
   ├── Inventory ──────► InventorySlot ──► Database
   ├── DialogueSystem ──► GameState, AudioManager
   └── FarmGrid ────────► Inventory, GameClock, EventBus

SaveManager ──► get_tree() groups เท่านั้น  (ไม่รู้จัก GameClock/GameState โดยตรง)
   ▲
   └── SceneLoader ──► GameState, GameClock, DialogueSystem

WorldSpace ◄──── (ทุกอย่างที่เกี่ยวกับพื้นที่)   static ล้วน ไม่พึ่งใคร
   ▲
   └── WorldObjectData ──► WorldBody ──► entity ทุกตัว
                       └─► PlaceholderVisual (ชั่วคราว ลบพร้อมงานศิลป์จริง)

Player ──► InteractionProbe, ToolHandler, StateMachine, FarmGrid, GameState
ToolHandler ──► Inventory, FarmGrid, GameState   (ไม่ type-ref Player — ดูข้างล่าง)
Npc / Bed / SignPost ──► Interactable ──► DialogueSystem, GameClock, GameState

UI (HUD, DialogueBox, InventoryPanel) ──► อ่าน autoload + ฟัง EventBus
                                          ไม่มีใครพึ่ง UI  ◄── สำคัญ
```

### ทิศทางที่ห้ามผิด

- `EventBus` และ `GameConstants` ไม่พึ่งใครเลย → ไม่มีทางเกิด cycle จากสองตัวนี้
- ไม่มีอะไรพึ่ง UI → ถอด/เปลี่ยน UI ทั้งชั้นได้โดยไม่กระทบ gameplay
- `SaveManager` พึ่งแค่ group ไม่พึ่งระบบใดโดยตรง → เพิ่มระบบไม่ต้องแตะ SaveManager

### cycle เดียวที่มีและวิธีเลี่ยง

`Player` ↔ `ToolHandler` เป็น cyclic class dependency เพราะ Player ประกาศ
`@onready var tool_handler: ToolHandler` อยู่แล้ว ดังนั้น `ToolHandler` จึงถือ
`var _player: Variant` **แบบไม่ระบุ type** โดยเจตนา แล้วแปลง type กลับทันที
ที่ขอบเขต (`var grid: FarmGrid = _player.farm_grid()`)

GDScript แก้ cycle แบบนี้ได้ไม่แน่นอน การตัดข้างเดียวชัดเจนกว่าปล่อยให้เสี่ยง

---

## 3. ระบบสำคัญ

| ระบบ | ไฟล์ | หน้าที่ | หมายเหตุออกแบบ |
|---|---|---|---|
| **Time** | `game_clock.gd` | เดินเวลา, วัน, ฤดู, ปี | แหล่งความจริงเดียว ทุกอย่างที่อิงวันฟัง signal ไม่นับวันเอง `absolute_day()` เป็น key ที่ทนการข้ามฤดู/ปี |
| **Save/Load** | `save_manager.gd` | ประสานงาน JSON + migration | 2 group, 2 เฟส มี `_migrate()` รอไว้แล้ว |
| **Farming** | `farm_grid.gd`, `soil_cell.gd`, `farm_debug_view.gd` | ดิน, น้ำ, การโต, เหี่ยว | sparse dict → ไร่ 200×200 ที่ยังไม่ขุดต้นทุน 0 โตวันละครั้งตอน `day_started` ไม่ใช่ทุกเฟรม · **model ไม่วาดอะไรเลย** `FarmDebugView` อ่านแล้ววาด เปลี่ยนไป TileMapLayer แก้ไฟล์เดียว |
| **Inventory** | `inventory.gd`, `inventory_slot.gd` | 30 ช่อง, hotbar 5 ช่อง | `add_item()` คืน "จำนวนที่ใส่ไม่ลง" ผู้เรียกจึงตัดสินใจได้ว่าจะทิ้งหรือปฏิเสธ ไม่บีบอัดช่อง เพราะ index 0–4 คือ hotbar |
| **Interaction** | `interactable.gd`, `interaction_probe.gd` | หา target ที่ดีที่สุดรอบตัว | วัตถุตัดสินว่า "interact แล้วเกิดอะไร" ผู้เล่นตัดสินแค่ "เมื่อไร" — เพราะ inversion นี้ NPC/เตียง/ป้ายจึงใช้ probe ตัวเดียวกัน |
| **Dialogue** | `dialogue_system.gd` + `dialogue_box.gd` | คุยทีละบรรทัด | runner ถือ state, box เป็น view เปล่า ๆ เปลี่ยน UI ได้ไม่กระทบ logic |
| **Scene flow** | `scene_loader.gd` | fade + threaded load + spawn point | ทุกการเปลี่ยนฉากผ่านที่นี่ ไม่มีใครเรียก `change_scene_to_file` เอง |
| **Economy** | `shipping_bin.gd`, `shop.gd`, `shop_data.gd` | ขายผลผลิต · ซื้อของ | ถังขาย ร้านซื้อ ไม่มีใครทำงานของอีกฝ่าย — **ที่เดียวที่เงินถูกสร้าง และที่เดียวที่ถูกทำลาย** · ราคามาจาก `ItemData` ไม่ใช่จากร้าน · ตรรกะทั้งหมดทดสอบได้โดยไม่ต้องเรนเดอร์ |
| **Audio** | `audio_manager.gd` | เพลง crossfade + SFX pool 12 ตัว | pool เพราะสร้าง player ต่อเสียงเดินจะกวน scene tree |
| **Settings** | `settings_manager.gd` | เสียง/จอ/ภาษา → `user://settings.cfg` | แยกจากเซฟ เพราะต้องรอดจากการลบเซฟทุกช่อง |

### ลำดับการวาด (2.5D)

**เท้าตัดสินระยะ ไม่ใช่หัว** — `WorldSpace.depth_key()` คืนค่าจากจุดที่วัตถุแตะพื้น
และ **จงใจไม่สนความสูง** ถ้าเรียงตามตำแหน่งภาพ ต้นไม้สูงจะทับคนที่ยืนข้าง ๆ
แค่เพราะภาพมันสูงกว่า

y_sort ของ Godot เรียงตาม screen y ซึ่งตรงกับโมเดลเราได้ **ก็ต่อเมื่อ** node ของ
วัตถุอยู่ที่จุดบนพื้นจริง และความสูงถูกชดเชยที่ลูก (sprite) เท่านั้น
ถ้ามีใคร "ยก" node ขึ้นเพื่อให้ดูสูง การเรียงจะพังเงียบ ๆ — จึงมีเทสต์ล็อกไว้

`FarmDebugView` วาดสองรอบ: ดินทั้งหมดก่อน (แบนราบ บังอะไรไม่ได้) แล้วพืชเรียง
หลังไปหน้า มิฉะนั้นดินของแถวหน้าจะทับพืชที่ยืนอยู่แถวหลัง

### จุดที่ลำดับสำคัญ (load-bearing)

`world.gd::_ready()` เรียงแบบนี้โดยเจตนา:
1. วางผู้เล่นที่ spawn point ที่ขอมา
2. `EventBus.world_ready` → `SaveManager` ฟื้นสถานะ node ในฉาก (ทับตำแหน่งถ้าเป็นการโหลดเซฟ)
3. เริ่มเดินเวลา — เพื่อไม่ให้เวลาผ่านระหว่างกำลังฟื้นสถานะ

และสิ่งที่ **ไม่มี** ในนั้นก็สำคัญเท่ากัน: ฉากนี้ไม่เคย `emit(day_started)`
การปลอม rollover เพื่อ refresh label จะทำให้ `FarmGrid` เดิน daily tick
และพืชทุกต้นโตขึ้นเงียบ ๆ ทุกครั้งที่โหลดเซฟ — บั๊กนี้ถูกพบและแก้ระหว่างสร้างโครงนี้

---

## 4. Technical debt ที่มีอยู่แล้ว (รู้ตัว)

จงใจแลกความเร็วในการตั้งต้น เรียงตามความเจ็บถ้าปล่อยไว้นาน

| # | หนี้ | ที่ | ผลถ้าไม่แก้ | แก้อย่างไร |
|---|---|---|---|---|
| 1 | ~~ยังไม่ได้เปิดใน Godot editor~~ **แก้แล้ว** | — | — | compile ผ่านบน Godot 4.7.2, boot สะอาดทั้ง main_menu และ world, smoke test 50/50 ผ่าน |
| 2 | **ไม่มี art asset** — วาดด้วย `_draw()` และ ColorRect | `farm_grid.gd`, props | เห็นภาพระบบได้แต่ขายไม่ได้ | ใส่ TileSet + sprite แทน `_draw()` (แยก model/view ไว้แล้ว) |
| 3 | **ไม่มี animation** ผู้เล่น | `player.gd` | ขยับแล้วไม่มีชีวิต, `swing_time` เป็นค่าคงที่แทนความยาว animation | เพิ่ม `AnimatedSprite2D` + ผูก `facing` และ FSM |
| 4 | **`FarmGrid` มีตัวเดียวต่อ save id** | `farm_grid.gd` `SAVE_ID` | ถ้ามี 2 แผนที่ที่ปลูกได้ save id จะชนกัน | ทำ save id ให้รวมชื่อแผนที่ |
| 5 | **`GameState.current_map` ตั้งค่าแค่แผนที่เดียว** | `scene_loader.gd` | เพิ่มแผนที่ที่ 2 แล้วโหลดเซฟจะกลับผิดที่ | ทำ map registry แล้วตั้ง `current_map` ทุกครั้งที่เปลี่ยนฉาก |
| 6 | **ธง "คุยวันนี้แล้ว" สะสมไม่มีขอบเขต** | `npc.gd` | `flags` โตขึ้นทุกวันต่อ NPC → ไฟล์เซฟบวมเรื่อย ๆ | เก็บ `last_talked_day` ต่อ NPC แทนการตั้งธงต่อวัน |
| 7 | **ไม่มี theme กลาง — และ UI ใหญ่เกินจนใช้ไม่ได้** | `src/ui/**`, `project.godot` | ยืนยันด้วยภาพจากเกมจริง: default font บน base viewport 640×360 ทำให้ตัวอักษรกิน 1/5 ของจอ และ hotbar ถูกตัดขอบล่าง | ทำ `resources/themes/main_theme.tres` ตั้ง font size ให้เข้ากับ base viewport (หรือขยาย base viewport) — **ไม่ต้องหาฟอนต์ไทยใหม่ ดูหมายเหตุข้างล่าง** |
| 8 | **HUD hotbar โชว์ตัวอักษรแทน icon** | `hud.gd` | ชั่วคราวเท่านั้น | ใส่ `TextureRect` เมื่อมี `ItemData.icon` |
| 9 | **`Database` สแกนโฟลเดอร์ตอน boot** | `database.gd` | O(จำนวนไฟล์) — ยังไม่เป็นปัญหา แต่จะเป็นเมื่อมีเป็นพัน | ทำ manifest resource ตอน build |
| 10 | **hotbar 5 ช่อง hardcode ใน input map** | `project.godot` | ขยายเป็น 10 ต้องแก้ 2 ที่ | ผูก hotbar กับ `InputMap` แบบวนลูป |

**หนี้ #6 อธิบายเพิ่ม:** `npc.gd` ตั้งธงชื่อ `talked_somchai_day_37` ทุกวัน
ธงเก่าไม่เคยถูกลบ เล่น 2 ปีเกม × 10 NPC = ~6,700 คีย์ในไฟล์เซฟ
มันจะไม่พังทันที แต่จะบวมเงียบ ๆ — ควรแก้ก่อนเพิ่ม NPC ตัวที่ 3

---

## 5. ระบบที่ยังขาด

**จำเป็นก่อนจะเรียกว่าเกม**
1. ~~Shop / เศรษฐกิจ~~ ✅ เฟส 2
2. ~~Shipping bin~~ ✅ เฟส 2
3. **แผนที่หลายผืน + ประตู** — `SceneLoader` รับ spawn point ไว้แล้ว แต่ยังมีแผนที่เดียว
4. **NPC schedule** — ตอนนี้ NPC ยืนนิ่ง ควรเป็น component แยกที่ขยับ body ไม่ใช่ยัดใน `npc.gd`
5. **Animation + audio จริง** — ทั้งสองระบบมีที่รอไว้แล้ว ขาดแต่ไฟล์

**จำเป็นก่อนจะปล่อยให้คนเล่น**
6. **Theme + ฟอนต์ไทย** — default theme ของ Godot ไม่มี glyph สระ/วรรณยุกต์ไทยครบ
7. **Localisation** — มี `display_name` กับ `display_name_th` คู่กันอยู่แล้ว แต่ยังไม่มี locale switch จริง (ตอนนี้ hardcode ไทยใน UI)
8. **Save slot UI ที่ลบ/เขียนทับได้** — `delete_slot()` มีแล้วแต่ไม่มีปุ่ม
9. **Controller / rebind** — input map มี deadzone รอไว้ แต่ยังไม่มีปุ่ม gamepad

**จำเป็นสำหรับสุขภาพโปรเจกต์ระยะยาว**
10. **ชุดทดสอบที่โตได้** — มี `tests/smoke_test.tscn` (50 ข้อ, headless, exit code ใช้เป็น CI gate ได้) แต่เป็น harness เขียนเองไม่ใช่ framework ยังขาด per-test isolation, fixture และ report — ย้ายไป GdUnit4 เมื่อชุดเทสต์โต
11. **CI + export preset** — ยังไม่มี `export_presets.cfg` (gitignore ไว้)
12. **git** — โฟลเดอร์นี้ยังไม่เป็น git repo เลย

---

## 6. ความเสี่ยง

เรียงตามความน่ากลัวจริง ไม่ใช่ตามลำดับตัวอักษร

| ระดับ | ความเสี่ยง | ทำไมน่ากลัว | ลดความเสี่ยงอย่างไร |
|---|---|---|---|
| ✅ | ~~โค้ดยังไม่เคยถูก compile~~ | ปิดแล้ว: Godot 4.7.2 ติดตั้งแล้ว compile ผ่าน boot สะอาด smoke test 50/50 | — |
| ✅ | ~~ยังไม่มี version control~~ | ปิดแล้ว: git repo + initial commit | remote คือ `git@github.com:pathai95441/life-of-siam.git` |
| 🟠 **กลาง** | **ทดสอบเฉพาะ headless** | smoke test ครอบ logic ล้วน แต่ยังไม่มีใครเห็นเกมรันบนจอจริง — input, กล้อง, y-sort, การจัดวาง UI ยังไม่ถูกยืนยันด้วยตา | เปิด editor กด F5 เล่นให้ครบลูป |
| 🟠 **กลาง** | **save format v1 ยังไม่นิ่ง** | ถ้าปล่อยให้คนเล่นก่อนที่ schema จะนิ่ง จะติดหนี้ migration ตลอดไป | ยังอย่าให้ใครเล่นจริงจนกว่า inventory/farm schema จะนิ่ง `_migrate()` รอไว้แล้ว |
| 🟠 **กลาง** | **สถาปัตยกรรมนี้ใหญ่กว่าที่โปรเจกต์ต้องการวันนี้** | 10 autoload กับ FSM สำหรับเกมที่มี 1 แผนที่ = over-engineering ถ้าเป้าคือ prototype เล็ก | ถ้าเป้าคือเกมยาว โครงนี้คุ้ม ถ้าเป้าคือทดลอง idea 2 สัปดาห์ ควรบอกผมให้ตัดทิ้งครึ่งหนึ่ง |
| ✅ | ~~ฟอนต์ไทยใน default theme จะพัง~~ | **การประเมินนี้ผิด** — ภาพจับจากเกมจริงแสดง "วันที่ 1 ฤดูใบไม้ผลิ ปีที่ 1" และ "สวัสดี! มาถึงไร่แล้วหรือ ที่นี่ดินดีนะ" โดยสระและวรรณยุกต์วางถูกตำแหน่งทั้งหมด default font ของ Godot 4.7 รองรับไทยได้ | ไม่ต้องทำอะไร งานที่เหลือคือ **ขนาด** ฟอนต์ ไม่ใช่ตัวฟอนต์ |
| 🟡 **ต่ำ** | **`gl_compatibility` renderer** | เลือกเพื่อรองรับเครื่องเก่า/เว็บ แต่ตัด feature 2D บางอย่างของ Forward+ (เช่น 2D shadow บางแบบ) | ประเมินอีกครั้งเมื่อรู้แน่ว่าจะลง platform ไหน แก้ที่ `project.godot` บรรทัดเดียว |
| 🟡 **ต่ำ** | **`_draw()` debug จะติดค้าง** | โค้ดชั่วคราวที่ "ใช้ได้" มักอยู่ยาว | ลบทิ้งพร้อมกับที่ใส่ TileSet ไม่ใช่ทีหลัง |

### ผลการ compile ครั้งแรก (Godot 4.7.2)

พบ error จริง **1 ตัว** จากทั้งโปรเจกต์:

```
Parse Error: Member "priority" redefined (original in native class 'Area2D')
  at res://src/components/interactable.gd:13
```

`Area2D` มี property `priority` ของตัวเองอยู่แล้ว (ลำดับการประมวลผล area) การ
`@export var priority` จึงเป็นการ shadow ซึ่ง GDScript ไม่ยอม — error ตัวเดียวนี้
ลามไปทำให้ 8 สคริปต์ที่พึ่ง `Interactable` compile ไม่ผ่านตามกันหมด
แก้โดยเปลี่ยนชื่อเป็น `focus_priority` (แก้ 4 ไฟล์: `interactable.gd`,
`interaction_probe.gd`, `bed.gd`, `bed.tscn`)

**บทเรียน:** ก่อน `@export` ชื่อสั้น ๆ บนคลาส engine ให้เช็คก่อนว่าชนกับ property
ดั้งเดิมไหม ชื่อเสี่ยงอื่น ๆ ที่ควรระวัง: `position`, `scale`, `visible`, `mode`,
`offset`, `size`, `speed`, `disabled`, `monitoring`

สิ่งที่ **ไม่** พบปัญหา แม้เขียนมือทั้งหมด:
- typed array ใน `.tres` — `Array[DialogueLine]([...])`, `Array[int]([...])` โหลดผ่าน
- `unique_name_in_owner` ทุกฉาก
- node-type export ที่ serialize เป็น NodePath (`npc_data`, `sprite_node`)
- `res://` ทั้ง 62 จุด
- `[Database] 7 items, 2 crops, 1 npcs, 1 dialogues` ตรงตามที่ควรเป็น

Godot 4.7 สร้างไฟล์ `.uid` ให้ทุกสคริปต์ตอน import — **ต้อง commit ไปด้วย**
เพราะเป็น identity ที่ Godot ใช้อ้างอิงสคริปต์ข้ามการเปลี่ยนชื่อไฟล์

---

## 7. ลำดับงานที่แนะนำ

ทำตามลำดับ แต่ละขั้นจบแล้ว "ยังเล่นได้" — ไม่มีขั้นไหนทำให้โปรเจกต์พังค้าง

### เฟส 0 — ทำให้มันรันจริง (ก่อนอย่างอื่นทั้งหมด)
1. ~~`git init` + commit โครงนี้~~ ✅
2. ~~ติดตั้ง Godot + ไล่แก้ compile error~~ ✅ (4.7.2, พบและแก้ error 1 ตัว)
3. ~~ยืนยัน core loop ด้วย headless test~~ ✅ (`tests/smoke_test.tscn`, 50/50)
4. **เหลืออยู่:** เปิด editor กด F5 เล่นด้วยมือให้ครบลูป — ยืนยันสิ่งที่ headless
   ทดสอบไม่ได้: input, กล้องตาม, y-sort, การจัดวาง UI, ฟอนต์ไทย
5. **เหลืออยู่:** push ขึ้น GitHub remote

**ยังไม่ต้องเขียน feature ใหม่จนกว่าข้อ 4 จะผ่าน**

### เฟส 1 — ปิดหนี้ที่แพงที่สุดก่อนมันแพงขึ้น
5. Theme กลาง + ฟอนต์ไทย (หนี้ #7 — แก้ทีหลังเจ็บกว่ามาก)
6. เขียนเทสต์ 3 ตัวแรก: `FarmGrid` daily tick, `Inventory.add_item` ตอนกระเป๋าเต็ม, save round-trip (ขาด #10)
7. แก้ธง NPC ให้เป็น `last_talked_day` (หนี้ #6 — แก้ก่อนเพิ่ม NPC)

### เฟส 2 — ปิดลูปเศรษฐกิจ (ตรงนี้เกมจะเริ่มสนุก)
8. `ShippingBin` — Interactable ที่กินของแล้วจ่ายเงินตอน `day_started`
9. `Shop` — ใช้ `buy_price` ที่มีอยู่ + `GameState.try_spend()` ที่เขียนรอไว้
10. UI ราคาและยอดขายรายวัน

### เฟส 3 — ขยายโลก
11. แผนที่ที่ 2 (บ้าน/หมู่บ้าน) + `Door` interactable → แก้หนี้ #4 และ #5 ตอนนี้ **ไม่ใช่ทีหลัง** เพราะเป็นตอนที่มันเริ่มเจ็บจริง
12. NPC schedule เป็น component แยก
13. NPC ตัวที่ 2–3 + ระบบให้ของขวัญ (`liked_items` มีอยู่แล้ว)

### เฟส 4 — ทำให้ดูเป็นเกม
14. TileSet + ลบ `_draw()` debug ทิ้ง (หนี้ #2)
15. `AnimatedSprite2D` ผูกกับ FSM + `facing` (หนี้ #3)
16. เสียงและเพลงจริง
17. Item icon ใน HUD และกระเป๋า (หนี้ #8)

### เฟส 5 — ปล่อยได้
18. Save slot UI ที่ลบ/เขียนทับได้
19. Localisation จริง (ไทย/อังกฤษ) — ข้อมูลคู่ภาษาเตรียมไว้แล้ว
20. Export preset + CI
21. Controller + rebind

### เหตุผลของลำดับนี้

- **เฟส 0 มาก่อนทุกอย่าง** เพราะเขียน feature บนโค้ดที่ยัง compile ไม่ผ่าน = เขียนบนทราย
- **theme กับเทสต์อยู่เฟส 1** เพราะทั้งสองอย่าง "ยิ่งช้ายิ่งแพง" — theme ต้องแก้ทุกฉากที่มีอยู่, เทสต์ต้องเขียนตอนที่ยังจำ requirement ได้
- **เศรษฐกิจมาก่อนแผนที่ที่ 2** เพราะมันปิด core loop ให้ครบ ทำให้ทดสอบความสนุกได้เร็ว ในขณะที่แผนที่เพิ่มแค่ปริมาณ
- **หนี้ #4/#5 แก้ตอนเฟส 3** เพราะมันเป็นหนี้ที่ "ไม่เจ็บจนกว่าจะมีแผนที่ที่ 2" — แก้ก่อนนั้นคือเดาอนาคต
- **art อยู่เฟส 4** เพราะ model/view แยกไว้แล้ว งานศิลป์จึงไม่บล็อกงานระบบ และระบบที่ยังไม่นิ่งไม่ควรมีคนมาวาดทับ
