# Siam Life — สถาปัตยกรรม

เอกสารนี้คือรายงาน 7 หัวข้อที่ตกลงกันไว้ เขียนจากโค้ดที่มีอยู่จริงในโปรเจกต์นี้
ปรับปรุงเมื่อโครงสร้างเปลี่ยน — ถ้าเอกสารกับโค้ดไม่ตรงกัน ให้ถือว่าเอกสารผิด

---

## 1. สถาปัตยกรรมปัจจุบัน

แบ่ง 4 ชั้น กฎคือ **ชั้นล่างไม่รู้จักชั้นบน**

```
ชั้นที่ 4  VIEW        HUD, DialogueBox, InventoryPanel, Menus
                       อ่านสถานะ + ฟัง EventBus เท่านั้น ห้ามเขียนสถานะเกม
                                    ▲ (signal)
ชั้นที่ 3  ENTITY      Player (FSM), Npc, Bed, SignPost
                       ตัวตนในฉาก ประกอบจาก component
                                    ▲
ชั้นที่ 2  SYSTEM      FarmGrid, InteractionProbe, ToolHandler, StateMachine
                       ตรรกะเกมที่จับต้องฉากได้
                                    ▲
ชั้นที่ 1  GLOBAL      autoload 10 ตัว — สถานะที่ต้องอยู่ข้ามฉาก
                       EventBus, SettingsManager, Database, AudioManager,
                       SaveManager, GameClock, GameState, Inventory,
                       DialogueSystem, SceneLoader
```

### หลักการที่ใช้ตัดสินใจ

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
| `saveable` | node ในฉากที่เกิด-ดับ (FarmGrid, Player) | หลังฉากเข้า tree แล้ว ผ่าน `EventBus.world_ready` |

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
| **Farming** | `farm_grid.gd`, `soil_cell.gd` | ดิน, น้ำ, การโต, เหี่ยว | sparse dict → ไร่ 200×200 ที่ยังไม่ขุดต้นทุน 0 โตวันละครั้งตอน `day_started` ไม่ใช่ทุกเฟรม |
| **Inventory** | `inventory.gd`, `inventory_slot.gd` | 30 ช่อง, hotbar 5 ช่อง | `add_item()` คืน "จำนวนที่ใส่ไม่ลง" ผู้เรียกจึงตัดสินใจได้ว่าจะทิ้งหรือปฏิเสธ ไม่บีบอัดช่อง เพราะ index 0–4 คือ hotbar |
| **Interaction** | `interactable.gd`, `interaction_probe.gd` | หา target ที่ดีที่สุดรอบตัว | วัตถุตัดสินว่า "interact แล้วเกิดอะไร" ผู้เล่นตัดสินแค่ "เมื่อไร" — เพราะ inversion นี้ NPC/เตียง/ป้ายจึงใช้ probe ตัวเดียวกัน |
| **Dialogue** | `dialogue_system.gd` + `dialogue_box.gd` | คุยทีละบรรทัด | runner ถือ state, box เป็น view เปล่า ๆ เปลี่ยน UI ได้ไม่กระทบ logic |
| **Scene flow** | `scene_loader.gd` | fade + threaded load + spawn point | ทุกการเปลี่ยนฉากผ่านที่นี่ ไม่มีใครเรียก `change_scene_to_file` เอง |
| **Audio** | `audio_manager.gd` | เพลง crossfade + SFX pool 12 ตัว | pool เพราะสร้าง player ต่อเสียงเดินจะกวน scene tree |
| **Settings** | `settings_manager.gd` | เสียง/จอ/ภาษา → `user://settings.cfg` | แยกจากเซฟ เพราะต้องรอดจากการลบเซฟทุกช่อง |

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
| 1 | **ยังไม่ได้เปิดใน Godot editor เลย** | ทั้งโปรเจกต์ | `.tscn`/`.tres` ที่เขียนมือมีโอกาสผิด format และ error จะโผล่ตอนเปิดครั้งแรก | เปิด, อ่าน Output panel, แก้ตามรายการ First-open checklist ข้างล่าง |
| 2 | **ไม่มี art asset** — วาดด้วย `_draw()` และ ColorRect | `farm_grid.gd`, props | เห็นภาพระบบได้แต่ขายไม่ได้ | ใส่ TileSet + sprite แทน `_draw()` (แยก model/view ไว้แล้ว) |
| 3 | **ไม่มี animation** ผู้เล่น | `player.gd` | ขยับแล้วไม่มีชีวิต, `swing_time` เป็นค่าคงที่แทนความยาว animation | เพิ่ม `AnimatedSprite2D` + ผูก `facing` และ FSM |
| 4 | **`FarmGrid` มีตัวเดียวต่อ save id** | `farm_grid.gd` `SAVE_ID` | ถ้ามี 2 แผนที่ที่ปลูกได้ save id จะชนกัน | ทำ save id ให้รวมชื่อแผนที่ |
| 5 | **`GameState.current_map` ตั้งค่าแค่แผนที่เดียว** | `scene_loader.gd` | เพิ่มแผนที่ที่ 2 แล้วโหลดเซฟจะกลับผิดที่ | ทำ map registry แล้วตั้ง `current_map` ทุกครั้งที่เปลี่ยนฉาก |
| 6 | **ธง "คุยวันนี้แล้ว" สะสมไม่มีขอบเขต** | `npc.gd` | `flags` โตขึ้นทุกวันต่อ NPC → ไฟล์เซฟบวมเรื่อย ๆ | เก็บ `last_talked_day` ต่อ NPC แทนการตั้งธงต่อวัน |
| 7 | **ไม่มี theme กลาง** | `src/ui/**` | UI ใช้ default theme, ฟอนต์ไทยยังไม่ได้ตั้ง | ทำ `resources/themes/main_theme.tres` + ฟอนต์ที่รองรับสระไทย |
| 8 | **HUD hotbar โชว์ตัวอักษรแทน icon** | `hud.gd` | ชั่วคราวเท่านั้น | ใส่ `TextureRect` เมื่อมี `ItemData.icon` |
| 9 | **`Database` สแกนโฟลเดอร์ตอน boot** | `database.gd` | O(จำนวนไฟล์) — ยังไม่เป็นปัญหา แต่จะเป็นเมื่อมีเป็นพัน | ทำ manifest resource ตอน build |
| 10 | **hotbar 5 ช่อง hardcode ใน input map** | `project.godot` | ขยายเป็น 10 ต้องแก้ 2 ที่ | ผูก hotbar กับ `InputMap` แบบวนลูป |

**หนี้ #6 อธิบายเพิ่ม:** `npc.gd` ตั้งธงชื่อ `talked_somchai_day_37` ทุกวัน
ธงเก่าไม่เคยถูกลบ เล่น 2 ปีเกม × 10 NPC = ~6,700 คีย์ในไฟล์เซฟ
มันจะไม่พังทันที แต่จะบวมเงียบ ๆ — ควรแก้ก่อนเพิ่ม NPC ตัวที่ 3

---

## 5. ระบบที่ยังขาด

**จำเป็นก่อนจะเรียกว่าเกม**
1. **Shop / เศรษฐกิจ** — `sell_price`/`buy_price` มีใน `ItemData` แล้ว แต่ไม่มีที่ให้ซื้อขาย
2. **Shipping bin** — ทางระบายผลผลิตเป็นเงิน หัวใจของ loop รายวัน
3. **แผนที่หลายผืน + ประตู** — `SceneLoader` รับ spawn point ไว้แล้ว แต่ยังมีแผนที่เดียว
4. **NPC schedule** — ตอนนี้ NPC ยืนนิ่ง ควรเป็น component แยกที่ขยับ body ไม่ใช่ยัดใน `npc.gd`
5. **Animation + audio จริง** — ทั้งสองระบบมีที่รอไว้แล้ว ขาดแต่ไฟล์

**จำเป็นก่อนจะปล่อยให้คนเล่น**
6. **Theme + ฟอนต์ไทย** — default theme ของ Godot ไม่มี glyph สระ/วรรณยุกต์ไทยครบ
7. **Localisation** — มี `display_name` กับ `display_name_th` คู่กันอยู่แล้ว แต่ยังไม่มี locale switch จริง (ตอนนี้ hardcode ไทยใน UI)
8. **Save slot UI ที่ลบ/เขียนทับได้** — `delete_slot()` มีแล้วแต่ไม่มีปุ่ม
9. **Controller / rebind** — input map มี deadzone รอไว้ แต่ยังไม่มีปุ่ม gamepad

**จำเป็นสำหรับสุขภาพโปรเจกต์ระยะยาว**
10. **ชุดทดสอบ** — `tests/` ว่างเปล่า ทั้ง `FarmGrid` daily tick, `Inventory.add_item` overflow และ save round-trip เป็น logic ล้วน ทดสอบได้ทันที (แนะนำ GdUnit4)
11. **CI + export preset** — ยังไม่มี `export_presets.cfg` (gitignore ไว้)
12. **git** — โฟลเดอร์นี้ยังไม่เป็น git repo เลย

---

## 6. ความเสี่ยง

เรียงตามความน่ากลัวจริง ไม่ใช่ตามลำดับตัวอักษร

| ระดับ | ความเสี่ยง | ทำไมน่ากลัว | ลดความเสี่ยงอย่างไร |
|---|---|---|---|
| 🔴 **สูง** | **โค้ดยังไม่เคยถูก compile** | ไม่มี Godot ในเครื่องนี้ ทุกอย่างเขียนจากความรู้ syntax GDScript 4.4 `.tscn`/`.tres` ที่เขียนมือคือจุดเสี่ยงที่สุด (`Array[DialogueLine](...)`, `unique_name_in_owner`, node-type export ที่ serialize เป็น NodePath) | เปิดใน editor แล้วไล่แก้ตาม checklist ข้างล่าง **ก่อนเขียนโค้ดเพิ่มแม้บรรทัดเดียว** |
| 🔴 **สูง** | **ยังไม่มี version control** | งาน refactor ที่จะตามมาย้อนกลับไม่ได้ | `git init` + commit โครงนี้เป็น commit แรก ก่อนแก้อะไร |
| 🟠 **กลาง** | **save format v1 ยังไม่นิ่ง** | ถ้าปล่อยให้คนเล่นก่อนที่ schema จะนิ่ง จะติดหนี้ migration ตลอดไป | ยังอย่าให้ใครเล่นจริงจนกว่า inventory/farm schema จะนิ่ง `_migrate()` รอไว้แล้ว |
| 🟠 **กลาง** | **สถาปัตยกรรมนี้ใหญ่กว่าที่โปรเจกต์ต้องการวันนี้** | 10 autoload กับ FSM สำหรับเกมที่มี 1 แผนที่ = over-engineering ถ้าเป้าคือ prototype เล็ก | ถ้าเป้าคือเกมยาว โครงนี้คุ้ม ถ้าเป้าคือทดลอง idea 2 สัปดาห์ ควรบอกผมให้ตัดทิ้งครึ่งหนึ่ง |
| 🟠 **กลาง** | **ฟอนต์ไทยใน default theme** | สระลอย/วรรณยุกต์ซ้อนผิดตำแหน่ง เห็นชัดทันทีที่เปิด และแก้ทีหลังเจ็บกว่า | ใส่ฟอนต์ไทย (เช่น Noto Sans Thai) + theme กลางตั้งแต่ต้น |
| 🟡 **ต่ำ** | **`gl_compatibility` renderer** | เลือกเพื่อรองรับเครื่องเก่า/เว็บ แต่ตัด feature 2D บางอย่างของ Forward+ (เช่น 2D shadow บางแบบ) | ประเมินอีกครั้งเมื่อรู้แน่ว่าจะลง platform ไหน แก้ที่ `project.godot` บรรทัดเดียว |
| 🟡 **ต่ำ** | **`_draw()` debug จะติดค้าง** | โค้ดชั่วคราวที่ "ใช้ได้" มักอยู่ยาว | ลบทิ้งพร้อมกับที่ใส่ TileSet ไม่ใช่ทีหลัง |

### First-open checklist

เปิด Godot ครั้งแรกแล้วคาดว่าอาจเจอ (เรียงตามโอกาสเจอ):

1. **UID warnings** — ไฟล์ที่เขียนมือไม่มี `uid://` Godot จะเตือนแล้วสร้างให้เอง
   → เปิดทุกฉากแล้ว `Ctrl+S` ทับ เพื่อให้ Godot เขียน uid ลงไป
2. **`icon.svg` import** — Godot ต้อง import svg ก่อน `player.tscn` จะอ้างถึงได้
   → ถ้า Sprite2D ว่าง ให้ลากไฟล์ใส่ใหม่
3. **typed array ใน `.tres`** — `Array[DialogueLine]([...])` และ `Array[int]([...])`
   → ถ้า error ให้เปิดไฟล์ `.tres` ใน Inspector แล้วใส่ค่าใหม่ แล้ว save
4. **node-type export** — `npc_data`, `sprite_node`, `world_music` ควรผูกมาแล้ว
   → เช็คใน Inspector ว่าไม่ว่าง
5. **`%UniqueName` ที่หลุด** — ถ้า `_ready` ตายเพราะหา node ไม่เจอ ให้เช็คว่า node นั้นมี `unique_name_in_owner` จริง
6. **`Database` output** — ถ้าเปิดเกมแล้ว console ไม่ขึ้น
   `[Database] 7 items, 2 crops, 1 npcs, 1 dialogues` แปลว่า `.tres` โหลดไม่ผ่าน

---

## 7. ลำดับงานที่แนะนำ

ทำตามลำดับ แต่ละขั้นจบแล้ว "ยังเล่นได้" — ไม่มีขั้นไหนทำให้โปรเจกต์พังค้าง

### เฟส 0 — ทำให้มันรันจริง (ก่อนอย่างอื่นทั้งหมด)
1. `git init` + commit โครงนี้
2. ติดตั้ง Godot 4.4 → import → ไล่แก้ error ตาม First-open checklist
3. เล่นให้ครบ loop: พลิกดิน → ปลูก → รดน้ำ → นอน → เก็บเกี่ยว → เซฟ → โหลด
4. commit "โครงที่รันได้จริง" — จุดนี้คือฐานที่ปลอดภัย

**ยังไม่ต้องเขียน feature ใหม่จนกว่าข้อ 3 จะผ่าน**

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
