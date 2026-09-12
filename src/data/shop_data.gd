class_name ShopData
extends Resource
## What one shop sells.
##
## Prices are not stored here: they come from [member ItemData.buy_price], so an
## item costs the same wherever it is sold and a price change is one edit. When
## shops eventually need to differ, add a multiplier here rather than a second
## copy of the number.
##
## Stock is unlimited in this version. Quantities would need restocking rules,
## a restock trigger and a save slot of their own; none of that is needed to
## close the economy loop.

@export var id: StringName = &""
@export var display_name_th: String = ""
## Item ids this shop offers, in display order.
@export var stock: Array[StringName] = []


func sells(item_id: StringName) -> bool:
	return stock.has(item_id)


## Every reason this shop is unusable, empty when it is fine. Text rather than
## a bool so a bad .tres names its own problem.
func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	if stock.is_empty():
		errors.append("stock is empty")
	for item_id in stock:
		var item := Database.get_item(item_id)
		if item == null:
			errors.append("stocks unknown item '%s'" % item_id)
		elif item.buy_price <= 0:
			errors.append("stocks '%s' which has no buy price" % item_id)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
