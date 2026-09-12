class_name Shop
extends Interactable
## Sells goods for money. The buying half of the economy; [ShippingBin] is the
## selling half, and neither does the other's job.
##
## Holds no UI and knows none exists. Every rule about what a purchase costs
## and whether it is allowed lives here, so it can all be tested without
## rendering anything -- which matters because this is where money is
## destroyed, and money bugs are the ones players never forgive.

@export var shop_data: ShopData


func _ready() -> void:
	super()
	if shop_data != null:
		prompt = "ซื้อของ"
		prompt_en = "Shop"


func interact(actor: Node) -> void:
	super(actor)
	if shop_data == null:
		push_error("Shop '%s' has no ShopData" % name)
		return
	EventBus.shop_opened.emit(self)


# --- Queries -----------------------------------------------------------------

func stock() -> Array[StringName]:
	return shop_data.stock.duplicate() if shop_data != null else [] as Array[StringName]


func sells(item_id: StringName) -> bool:
	return shop_data != null and shop_data.sells(item_id)


## Unit price, or 0 when this shop does not sell the item.
func price_of(item_id: StringName) -> int:
	if not sells(item_id):
		return 0
	var item := Database.get_item(item_id)
	return item.buy_price if item != null else 0


func total_price(item_id: StringName, amount: int) -> int:
	return price_of(item_id) * maxi(amount, 0)


## Whether a purchase would succeed, without attempting it. [method buy] does
## not rely on this -- it repeats the checks -- so a caller skipping it can
## still never lose money.
func can_buy(item_id: StringName, amount: int = 1) -> bool:
	return _refusal_reason(item_id, amount).is_empty()


# --- Buying ------------------------------------------------------------------

## Buys [param amount] of [param item_id]. Returns false and changes nothing at
## all when refused.
##
## Order is the whole point: every condition is checked before a single coin
## moves. Taking the money first and discovering the bag is full afterwards is
## the classic way to delete a player's savings.
func buy(item_id: StringName, amount: int = 1) -> bool:
	var reason := _refusal_reason(item_id, amount)
	if not reason.is_empty():
		EventBus.purchase_refused.emit(item_id, reason)
		EventBus.toast_posted.emit(reason)
		return false

	var cost := total_price(item_id, amount)
	if not GameState.try_spend(cost):
		# Unreachable after the affordability check above, but money is worth
		# a belt as well as braces.
		EventBus.purchase_refused.emit(item_id, "จ่ายเงินไม่สำเร็จ")
		return false

	var leftover := Inventory.add_item(item_id, amount)
	if leftover > 0:
		# can_accept said it would fit. If it did not, refund rather than let
		# the player pay for goods they never received.
		push_error("Shop: %d of '%s' did not fit after can_accept passed; refunding"
			% [leftover, item_id])
		GameState.add_money(price_of(item_id) * leftover)

	EventBus.item_purchased.emit(item_id, amount - leftover, cost)
	EventBus.toast_posted.emit("ซื้อ %s x%d" % [_label_of(item_id), amount - leftover])
	return true


## Empty when the purchase is allowed; otherwise why it is not.
func _refusal_reason(item_id: StringName, amount: int) -> String:
	if shop_data == null:
		return "ร้านนี้ยังไม่เปิด"
	if amount <= 0:
		return "จำนวนไม่ถูกต้อง"
	if not sells(item_id):
		return "ร้านนี้ไม่ขายของชิ้นนี้"
	if price_of(item_id) <= 0:
		return "ของชิ้นนี้ไม่มีราคาขาย"
	if not Inventory.can_accept(item_id, amount):
		return "กระเป๋าเต็ม"
	if GameState.money < total_price(item_id, amount):
		return "เงินไม่พอ"
	return ""


func _label_of(item_id: StringName) -> String:
	var item := Database.get_item(item_id)
	return item.label() if item != null else String(item_id)
