# IMPLEMENTATION_PLAN.md

แผนเดิม 5 เฟสอยู่ใน `docs/ARCHITECTURE.md` §7 — **ไฟล์นี้ไม่ลบแผนเดิม** แต่แทรก
เฟส 2.5D เข้ามาก่อนเฟส 1 เพราะทิศทางภาพเปลี่ยน (ดูเหตุผลใน "ทำไมต้องแทรก")

## สถานะเฟส

| เฟส | ชื่อ | สถานะ |
|---|---|---|
| 0 | ทำให้รันจริง | 🟢 5/5 — เห็นภาพจากเกมจริงแล้ว (`tests/capture.tscn`) |
| **V** | **HUD & camera readability (D6–D8)** | 🟢 เสร็จ |
| **W** | **World-object model (2.5D foundation)** | 🟢 **เสร็จครบ W1–W8 · DoD ผ่าน 7/7** |
| 1 | Theme + ฟอนต์ไทย + เทสต์ | ⬜ รอ |
| 2 | ปิดลูปเศรษฐกิจ (shipping bin, shop) | 🔵 กำลังทำ — E1 ✅ E2 ✅ |
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
| `GAME_DESIGN.md` §2 canonical scale ที่พี่ยืนยันแล้ว | ✅ **32 px/wu** |
| ตัดสินใจโปรเจกชัน (oblique vs isometric) | ✅ **oblique 3/4** |
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

ชุดเทสต์ปัจจุบัน **333 assertion ผ่านทั้งหมด**
headless: `world_space` 35 · `world_object_data` 73 · `world_body` 20 · `projection` 29 · `entity` 47 · `economy` 26 · `shop` 32 · `smoke` 50 · `world` 16
windowed: `depth_sort` 5 (**ห้ามใส่ `--headless`** — headless เรนเดอร์ไม่ได้จึงตรวจลำดับการวาดจริงไม่ได้)

| Task | ทำอะไร | ผลที่ทดสอบได้ |
|---|---|---|
| ~~**W1**~~ ✅ | `core/world_space.gd` — โปรเจกชัน world↔screen, footprint rect, depth key ทั้งหมดเป็น static | **เสร็จ: `tests/world_space_test.tscn` 35/35** |
| ~~**W2**~~ ✅ | `data/world_object_data.gd` — Resource: footprint, height, origin, blocks_movement, interaction_reach + `.tres` 4 ตัว | **เสร็จ: `tests/world_object_data_test.tscn` 57/57** |
| ~~**W3**~~ ✅ | `components/world_body.gd` — สร้าง collision + interaction shape จาก data ตอน `_ready` | **เสร็จ: `tests/world_body_test.tscn` 20/20** |
| ~~**W4**~~ ✅ | ย้าย `Player` มาใช้ `world_body` ลบ shape ที่ hardcode | **เสร็จ: `world_test` 13→32 · probe reach band วัดได้ · sprite derive จาก data** |
| ~~**W5**~~ ✅ | ย้าย `Npc` / `Bed` / `SignPost` มาใช้ `world_body` | **เสร็จ: `world_test` 32→60 · DoD ข้อ 1 ปิด · reach band กว้างขึ้นวัดได้** |
| ~~**W6**~~ ✅ | `FarmGrid` เรียก `WorldSpace` · movement/targeting เข้า projected space · แยก `FarmDebugView` ออกจาก model | **เสร็จ: `projection_test` 21/21 · D13 ปิด · `TILE_SIZE` ถูกลบทั้งโปรเจกต์** |
| ~~**W7**~~ ✅ | depth sorting ด้วย world y | **เสร็จ: `depth_sort_test` อ่านพิกเซลจริง 5/5 · `FarmDebugView` วาดสองรอบเรียงด้วย `depth_key` · invariant ของ entity ล็อกด้วยเทสต์** |
| ~~**W8**~~ ✅ | ซอย `smoke_test.gd` · `change_scene` · `world_test.gd` | **เสร็จ: assertion ไม่ลดสักข้อ · เพดานผ่านทั้งโปรเจกต์** |

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
| ✅ | ~~ยังไม่ยืนยัน canonical scale~~ | ปิดแล้ว: 32 px/wu · ค่าอยู่ใน `GameConstants` 3 ตัว ใช้ผ่าน `WorldSpace` เท่านั้น แก้ที่เดียวจบ |
| ✅ | ~~โปรเจกชันยังไม่ตัดสินใจ~~ | ปิดแล้ว: oblique 3/4 · W1 ยังออกแบบให้สลับสูตรได้ที่จุดเดียว |
| 🟠 | refactor `FarmGrid`/`InteractionProbe` ที่ทำงานอยู่แล้วอาจพัง | `smoke_test` เป็น baseline · W6 อยู่ท้ายสุด · ทำ task ละ commit |
| 🟠 | y_sort ของ Godot เรียงด้วย screen y ไม่ใช่ world y — พอมี depth ratio อาจเรียงผิด | W7 มีเทสต์ฉากเฉพาะ + ต้องยืนยันด้วยตา |
| 🟡 | over-engineering — สร้าง abstraction เกินที่เกมต้องใช้ | ยึดกฎ: ทำแค่ที่ 8 magic number ปัจจุบันต้องใช้ ไม่เพิ่ม field เผื่ออนาคต |

---

---

# PHASE 2 — Economy loop

> **ร่างโดย agent รอพี่ยืนยัน** — ทุกข้อที่ทำเครื่องหมาย ❓ คือสิ่งที่ผมเลือกให้ ไม่ใช่สิ่งที่พี่บอก
> แก้ตรงไหนก็ได้ ผมจะยึดไฟล์นี้ ไม่ยึดสิ่งที่ผมเดาไว้

## PHASE OBJECTIVE

ทำให้ผลผลิตเปลี่ยนเป็นเงินได้ และเงินซื้อของได้ — **ปิด core loop**

ตอนนี้ปลูกและเก็บเกี่ยวได้ แต่ไม่มีอะไรให้ทำกับผลผลิต `sell_price` `buy_price`
`GameState.try_spend()` มีและผ่านเทสต์แล้ว แต่ไม่มีใครเรียกใช้ — เฟสนี้คือการต่อปลายทั้งสองเข้าหากัน

**ไม่อยู่ในขอบเขต:** อาคารร้านค้า, เวลาเปิด-ปิด, การต่อราคา, ระบบราคาผันผวน,
แผนที่ใหม่ (เฟส 3), งานศิลป์ (เฟส 4)

## DEPENDENCIES

| ต้องมีก่อน | สถานะ |
|---|---|
| `Inventory` (add/remove/can_accept) | ✅ ผ่านเทสต์ |
| `GameState.money` / `add_money` / `try_spend` | ✅ ผ่านเทสต์ แต่ยังไม่มีใครเรียก |
| `GameClock.day_started` | ✅ |
| `SaveManager` group `saveable` | ✅ |
| `WorldObjectData` + `WorldBody` + `Interactable` | ✅ จากเฟส W |
| `ItemData.sell_price` / `buy_price` ที่ authored แล้ว | ✅ หัวผักกาด 35 · พริก 55 · เมล็ด 20/30 |
| ตัดสินใจ 4 ข้อข้างล่าง | ✅ **ยืนยันแล้วทั้งหมด** |

## ✅ ตัดสินใจแล้ว

| # | คำถาม | ตัดสินใจ | ทำไม |
|---|---|---|---|
| 1 | **ฝากของยังไง** | กด `E` ที่ถัง = ฝาก**ทั้ง stack ที่ถืออยู่** | เล็กที่สุดที่ทดสอบได้ UI เลือกของค่อยมาทีหลัง |
| 2 | **ขายที่ไหน ซื้อที่ไหน** | **ถังส่งของ = ขายอย่างเดียว · ร้าน = ซื้ออย่างเดียว** | ตรงแนวเกม และไม่มีตรรกะขายซ้ำสองที่ |
| 3 | **ร้านเป็นอะไร** | prop แผงลอยในแผนที่เดิม เปิดตลอด | อาคาร/เวลาเปิดเป็นงานเฟส 3 |
| 4 | **ได้เงินเมื่อไร** | **เช้าวันถัดไป** ตอน `day_started` | ให้การนอนมีความหมาย และมี trigger ที่ทดสอบได้ชัด |

## ARCHITECTURAL IMPACT

**ไม่เพิ่มชั้นใหม่** ใช้โครงที่มีอยู่ทั้งหมด

```
data/      shop_data.gd        ← ใหม่: Resource ระบุว่าร้านขายอะไร
systems/   economy/
             shipping_bin.gd   ← ใหม่: Interactable + saveable
             shop.gd           ← ใหม่: Interactable + ตรรกะซื้อขายล้วน
ui/        shop_panel.gd       ← ใหม่: view เปล่า ๆ ฟัง EventBus
```

**dependency:** `ShopData` → `Database` (registry ที่ 6) · `Shop`/`ShippingBin` →
`Inventory` + `GameState` + `GameClock` · `ShopPanel` → ไม่มีใครพึ่ง (ชั้น view)

**สิ่งที่ต้องไม่เกิด:** ตรรกะซื้อขายอยู่ใน UI — ต้องอยู่ใน `Shop` เพื่อทดสอบได้
โดยไม่ต้องเรนเดอร์ `ShopPanel` แค่เรียกและแสดงผล

**signal ใหม่ใน EventBus:** `items_shipped(total: int, count: int)` ·
`item_purchased(item_id, amount, cost)` · `purchase_refused(item_id, reason)`

## TASK BREAKDOWN

| Task | ทำอะไร | ผลที่ทดสอบได้ |
|---|---|---|
| ~~**E1**~~ ✅ | `ShippingBin` — Interactable รับของ เก็บไว้จนเช้า แล้วจ่ายเงิน · saveable · `wo_shipping_bin.tres` | **เสร็จ: `tests/economy_test.tscn` 26/26 ครบทุกเคสบั๊กคลาสสิก + invariant มูลค่า** |
| ~~**E2**~~ ✅ | `ShopData` + `Shop` — ตรรกะซื้อล้วน ไม่มี UI | **เสร็จ: `tests/shop_test.tscn` 32/32 · ทุก refusal path ยืนยันว่าไม่มีอะไรเปลี่ยนเลย** |
| **E3** | `ShopPanel` — UI รายการของ ราคา ปุ่มซื้อ | เปิด/ปิดได้ · รายการตรงกับ `ShopData` · กดซื้อแล้วเงินและกระเป๋าเปลี่ยน |
| **E4** | สรุปรายได้ตอนเช้า + toast | `day_started` แล้วขึ้นยอดขายเมื่อวาน |
| **E5** | วาง `ShippingBin` + `Shop` ลง `world.tscn` + เทสต์ integration | เดินไปกด `E` ได้จริงทั้งสอง · reach band ครอบ probe |

## TASK ORDER

`E1 → E2 → E3 → E4 → E5`

E1 ก่อนเพราะเป็นครึ่งที่ทำให้เกม**มีจุดหมาย**ทันที (ปลูก→ขาย→มีเงิน) และไม่ต้องมี UI ใหม่เลย
E2 แยกจาก E3 เพื่อให้ตรรกะเงินถูกทดสอบครบก่อนมี UI มาบัง
E5 ท้ายสุดเพราะแตะฉากที่ใช้งานอยู่

## TEST STRATEGY

| ชั้น | ใช้กับ | วิธี |
|---|---|---|
| **Unit** | `ShopData` validation · การคำนวณราคา | เรียกตรง ไม่ต้องมีฉาก |
| **Integration** | `ShippingBin` ข้ามวัน · `Shop.buy()` | ฉากเทสต์ instance node จริง + ขยับ `GameClock` |
| **Invariant** | **เงินต้องไม่ถูกสร้างหรือทำลาย** | ก่อน/หลังทุกธุรกรรม: `money + มูลค่าของในกระเป๋า + มูลค่าในถัง` เปลี่ยนตามที่คาดเท่านั้น |
| **Regression** | ทุก task | 259 assertion เดิมต้องผ่านครบ |
| **Manual** | E3, E5 | กด F5 ซื้อ-ขายจริง |

**เคสที่ต้องมีเทสต์ เพราะเป็นบั๊กคลาสสิก:**
- ซื้อตอนกระเป๋าเต็ม → **ห้ามหักเงิน** (เงินหายของไม่ได้)
- ฝากของตอนถังเต็ม/ของว่าง → ห้ามได้เงินฟรี
- โหลดเซฟที่บันทึกไว้**ก่อน**นอน → ของในถังต้องยังอยู่ครบ
- นอนสองคืนติด → ห้ามจ่ายซ้ำ

## DEFINITION OF DONE

1. ปลูก → เก็บ → ฝากถัง → นอน → **เงินเพิ่มตาม `sell_price` จริง**
2. เปิดร้าน → ซื้อเมล็ด → เงินลด ของเข้ากระเป๋า
3. เงินไม่พอ หรือกระเป๋าเต็ม → **ไม่มีอะไรเปลี่ยนเลย**
4. ของในถังรอด save/load
5. ตรรกะเงินทั้งหมดทดสอบได้โดยไม่ต้องเรนเดอร์
6. เทสต์เดิม 259 ผ่านครบ + เทสต์ใหม่ผ่าน
7. ไฟล์ ≤250 · ฟังก์ชัน ≤40
8. `ARCHITECTURE.md` เพิ่ม economy เข้าตารางระบบ

## RISKS

| ระดับ | ความเสี่ยง | ลดอย่างไร |
|---|---|---|
| 🔴 | **บั๊กเงินหาย/เงินงอก** — ผู้เล่นให้อภัยยากที่สุด | เทสต์ invariant มูลค่ารวมทุกธุรกรรม · `try_spend` คืน false โดยไม่แตะอะไรอยู่แล้ว |
| 🟠 | **ของในถังหายตอนเซฟ** — ผู้เล่นเสียผลผลิตทั้งวัน | `ShippingBin` เป็น `saveable` **ตั้งแต่ task แรก** ไม่ใช่เพิ่มทีหลัง |
| 🟠 | จ่ายซ้ำถ้า `day_started` ยิงสองครั้ง | ล้างถังในธุรกรรมเดียวกับการจ่าย + เทสต์นอนสองคืน |
| 🟡 | ราคายังไม่ balance | ราคาอยู่ใน `.tres` แก้ได้โดยไม่แตะโค้ด · balance เป็นงานหลังเกมเล่นได้ |
| 🟡 | ฝาก "ทั้ง stack" อาจใช้งานไม่ถนัด | เป็นการตัดสินใจ ❓1 · ถ้าไม่ถนัดเพิ่ม UI เลือกของทีหลัง ไม่กระทบตรรกะ |

## DISCOVERED TASKS

| # | งาน | กฎที่ผิด | เสนอทำที่ |
|---|---|---|---|
| D15 | **พืชวาดหลัง entity เสมอ** — `FarmDebugView` เป็น node เดียวใต้ `FarmGrid` จึงมี sort key เดียว ผู้เล่นที่ยืนหลังพืชสูงไม่ถูกบัง | 2.5D | เฟส 4 พร้อมงานศิลป์ (พืชเป็น sprite ต่อ cell ในชั้นที่ sort แล้ว) |

พบระหว่างตรวจโปรเจกต์ตามกฎใหม่ ยังไม่จัดเข้าเฟส

| # | งาน | กฎที่ผิด | เสนอทำที่ |
|---|---|---|---|
| D1 | ~~`smoke_test.gd::_ready` ยาว 125 บรรทัด~~ | ฟังก์ชัน ≤ 40 | ✅ W8 — ซอยเป็น 10 ส่วนตามลำดับการเล่น |
| D2 | ~~`scene_loader.gd::change_scene` 49 บรรทัด~~ | ฟังก์ชัน ≤ 40 | ✅ W8 — แยก `_begin_change` / `_swap_to` / `_abort_change` + เทสต์ guard |
| D3 | collision magic number 8 จุด | no magic numbers | = Task W3–W5 |
| D4 | ธง `talked_<npc>_day_<n>` สะสมไม่มีขอบเขต ทำไฟล์เซฟบวม | หนี้ #6 เดิม | เฟส 1 (ก่อนเพิ่ม NPC) |
| D5 | ไม่มี `AGENTS.md` / `IMPLEMENTATION_PLAN.md` | — | ✅ เสร็จแล้ว |
| D6 | ~~UI ใหญ่เกินใช้งาน~~ | — | ✅ เฟส V — `main_theme.tres` |
| D7 | ~~hotbar ถูกตัดขอบล่างจอ~~ | — | ✅ เฟส V — cell แสดงเลขปุ่ม+จำนวน ชื่อเต็มอยู่เหนือ hotbar |
| D8 | ~~กล้องไม่มี limit~~ | — | ✅ เฟส V — `World.bounds` → `Player.set_camera_limits()` + ขยายโลกเป็น 960×720 |
| D13 | ~~movement/targeting ยังไม่ project~~ | 2.5D | ✅ W6 — ความเร็วพื้น 2.200 wu/s เท่ากันทุกทิศ · screen px ต่างกันตาม depth ratio เป๊ะ |
| D12 | ~~ขนาดที่ data สั่งต่างจากที่ฉากจิ้มไว้มาก~~ | — | ✅ W5 — ยืนยันด้วยภาพและ reach band ที่กว้างขึ้น |
| D14 | **`sprite_node` ใน `npc.tscn` เป็น null มาสองงาน** เพราะขาด `node_paths=` — ไม่มี error ไม่มี warning | — | ✅ W5 + มีเทสต์กันไว้แล้ว |
| D11 | **ตัด string ไทยด้วย `.left(n)` ทำให้วรรณยุกต์หลุด grapheme** — พบและแก้แล้วใน hotbar แต่เป็นกับดักที่จะเกิดซ้ำ | — | ✅ แก้ที่ต้นเหตุ (เลิกตัดชื่อ) · บันทึกเป็นข้อห้ามใน AGENTS.md |
| D9 | ~~scale ไม่สอดคล้อง~~ | 2.5D rule 18 | ✅ W5 ครบทุกตัว — `PlaceholderVisual` derive ขนาดจาก data ที่เดียว |
| D10 | ~~ฟอนต์ไทยจะพัง~~ **ไม่จริง** — default font ของ Godot 4.7 เรนเดอร์ไทยถูกต้อง | — | ปิด ไม่ต้องทำ |
