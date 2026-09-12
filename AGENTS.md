# AGENTS.md — วิธีทำงานกับโปรเจกต์นี้

เอกสารนี้คือกฎการทำงาน อ่านก่อนแก้โค้ดทุกครั้ง
เจ้าของโปรเจกต์: Pathai · บทบาทของ agent: Lead Game Engineer

## อ่านอะไรก่อน

| ลำดับ | ไฟล์ | ใช้ตัดสินอะไร |
|---|---|---|
| 1 | `AGENTS.md` (ไฟล์นี้) | วิธีทำงาน, กฎที่ห้ามละเมิด |
| 2 | `GAME_DESIGN.md` | ตัวเกมคืออะไร, canonical scale, ข้อมูล gameplay |
| 3 | `docs/ARCHITECTURE.md` | โครงสร้างจริง, technical debt, ความเสี่ยง |
| 4 | `IMPLEMENTATION_PLAN.md` | เฟส, task, definition of done |

## ภาษา

- **prose ที่คุยกับเจ้าของโปรเจกต์ / เอกสาร / string ในเกม → ภาษาไทย**
- **identifier / `##` doc comment / commit message → ภาษาอังกฤษ**

## คำสั่งที่ต้องรันได้ทุกครั้งก่อนบอกว่าเสร็จ

```bash
# import + ตรวจ parse error (ต้องรันก่อนเสมอเมื่อมีไฟล์ใหม่)
godot --headless --path . --editor --quit

# ชุดเทสต์ headless — exit code ต้องเป็น 0 ทุกตัว
for t in world_space_test world_object_data_test world_body_test \
         projection_test smoke_test world_test; do
  godot --headless --path . tests/$t.tscn
done

# เทสต์ที่ต้องเรนเดอร์จริง — ห้ามใส่ --headless
godot --path . tests/depth_sort_test.tscn
```

⚠️ **`--editor --quit` ไม่ใช่ full compile check** — มันไม่รายงานการอ้าง const ที่ถูกลบ
ไปแล้ว เทสต์เท่านั้นที่จับได้ อย่าถือว่า "compile clean" แปลว่าปลอดภัย

Godot 4.7.2 อยู่ใน PATH เป็น `godot`

**ห้ามรายงานว่าสำเร็จถ้าไม่ได้รันสองคำสั่งนี้จริง**

## กฎที่ห้ามละเมิด

### กระบวนการ
1. ตรวจของที่มีอยู่ก่อนแก้ ค้นด้วย `grep`/`find` — **ห้ามสมมติว่าระบบไม่มี**
2. ห้ามเขียนระบบที่ทำงานอยู่แล้วใหม่ เว้นแต่มีเหตุผลทางสถาปัตยกรรมที่หนักแน่น
3. ใช้ของที่มีอยู่ซ้ำ ห้ามทำฟังก์ชันซ้ำซ้อน
4. ห้ามสร้าง abstraction ที่ยังไม่จำเป็น
5. ทำทีละ task ที่ทดสอบผลได้ ห้ามลุยทั้งเฟสรอบเดียว
6. ห้ามทำเฟสอนาคต เว้นแต่เป็น dependency — ถ้าจำเป็นให้ทำ **interface ขั้นต่ำ** เท่าที่เฟสนี้ต้องใช้

### โค้ด
7. ใช้ typed GDScript
8. ข้อมูล gameplay อยู่ใน Resource ห้าม hardcode
9. dependency ชี้ทางเดียว ห้าม circular
10. ไฟล์ไม่ใหญ่ ฟังก์ชันไม่ใหญ่ — เพดานที่ใช้ในโปรเจกต์นี้: **ไฟล์ ≤ 250 บรรทัด, ฟังก์ชัน ≤ 40 บรรทัด**
11. ห้าม magic number ในตรรกะเกม
12. composition ก่อน inheritance
13. ห้าม god class / giant manager
14. `@export` ชื่อสั้นต้องเช็คก่อนว่าชนกับ property ของคลาส engine ไหม — **มันเป็น parse error ไม่ใช่ warning** (เคยเสียเวลาไปกับ `priority` บน `Area2D` ที่ลาม 8 สคริปต์) ชื่อเสี่ยง: `position` `scale` `visible` `mode` `offset` `size` `speed` `disabled` `monitoring` `priority`

### เขียนไฟล์ .tscn ด้วยมือ
14a. **exported node reference ต้องมี `node_paths=` ใน header ของ node** ไม่ใช่แค่
    `NodePath(...)` ในตัว property เช่น
    `[node name="WorldBody" type="Node" parent="." node_paths=PackedStringArray("collision_body")]`
    ถ้าขาด `node_paths=` Godot จะ**ไม่ resolve** ให้เป็น node reference แล้ว property
    จะเป็น `null` เงียบ ๆ ไม่มี error — เสียเวลาไปแล้วครั้งหนึ่งกับ `player.tscn`
    ถ้าไม่แน่ใจ format ให้ Godot เขียนเอง: instantiate ฉาก ตั้งค่า แล้ว
    `PackedScene.pack()` + `ResourceSaver.save()` ทับไฟล์ แล้วอ่านผลลัพธ์
14e. **script ที่ถูกอ้างจากภายนอกต้องมี `class_name`** — ถ้า test ถือ node ไว้ในตัวแปร
    ที่ type เป็นคลาส engine (เช่น `CanvasLayer`) การเรียก **method** ยังผ่านแบบ dynamic
    แต่การอ่าน **const หรือ property** ของสคริปต์จะ resolve แบบ static แล้วพัง
    ใส่ `class_name` แล้ว type ตัวแปรให้ตรง ปัญหาหายทั้งหมด
14d. **ถ้าสคริปต์ของฉากที่สั่งรัน parse ไม่ผ่าน Godot headless จะค้าง ไม่ใช่ออกด้วย error**
    ถ้ารันแล้วไม่มี output เลย ให้สงสัย parse error ก่อน แล้วเช็คด้วย
    `--editor --quit` ซึ่งรายงาน parse error ตรง ๆ (`pkill -9 -f "godot "` เพื่อล้าง
    process ที่ค้าง — pattern `Godot.app/...` ไม่แมตช์เพราะรันผ่าน symlink `godot`)

### ข้อความไทย
14b. **ห้ามตัด string ไทยด้วย `.left(n)` / `.substr()` ตามจำนวนตัวอักษร** — ภาษาไทยมี
    grapheme cluster (พยัญชนะ + สระ + วรรณยุกต์) การตัดกลาง cluster ทำให้วรรณยุกต์
    ลอยหลุด เคยเกิดกับ hotbar ที่ตัด "เมล็ดหัวผักกาด" เป็น "เมล็" ถ้าพื้นที่ไม่พอ
    ให้ใช้ `clip_contents = true` หรือย้ายข้อความไปที่ที่กว้างพอ **ห้ามตัดเอง**
14c. ฟอนต์ default ของ Godot 4.7 รองรับไทยถูกต้องแล้ว ไม่ต้องหาฟอนต์ใหม่

### พื้นที่และขนาด (2.5D)
15. **ห้ามใช้ขนาด sprite เป็นขนาดใน gameplay** — sprite เปลี่ยนได้ กฎเกมต้องไม่เปลี่ยนตาม
16. ทุก world object ต้องแยก 4 อย่างออกจากกันชัดเจน:
    - **logical footprint** — ที่ยืนบนพื้น (กฎเกมใช้อันนี้)
    - **collision bounds** — สิ่งที่กันการเดิน
    - **interaction bounds** — ระยะที่กด E ติด
    - **visual bounds** — กรอบภาพ ใช้แค่วาดและ sort
17. ขนาดทุกอย่างมาจาก Resource ไม่ใช่ตัวเลขในไฟล์ `.tscn`
18. scale ต้องคงที่ข้าม Player / NPC / Tree / Building / Fence / Props — ดูตารางใน `GAME_DESIGN.md`

## สถานะปัจจุบัน

- git: `main` ผูก `git@github.com:pathai95441/life-of-siam.git` (SSH ใช้งานได้)
- Godot 4.7.2 · renderer `gl_compatibility`
- ทิศทางภาพ: **2.5D** — ตัวละคร 2D sprite, สิ่งแวดล้อมดูเป็น 3D (ตัดสินใจแล้ว ไม่ใช่ 2D top-down เดิม)
- ยังไม่มีใครเห็นเกมรันบนจอจริง — headless ผ่านหมดแต่ยังไม่ได้กด F5

## รูปแบบรายงานหลังจบแต่ละ task

```
TASK / STATUS / FILES CHANGED / IMPLEMENTATION SUMMARY
TESTS RUN / TEST RESULTS / KNOWN ISSUES / NEXT TASK
```
