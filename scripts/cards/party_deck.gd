class_name PartyDeck
extends RefCounted
## The single shared combat deck: draw pile, hand, discard pile and exhaust pile.
## Built from every party member's owned cards; ownership is kept on each CardInstance.

signal piles_changed
signal reshuffled

const MAX_HAND_SIZE := 10

var draw_pile: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []
var exhaust_pile: Array[CardInstance] = []
## Cards of fallen owners: out of every pile for the rest of the combat (never drawn, never shuffled back).
var set_aside: Array[CardInstance] = []

var _rng: RandomNumberGenerator
var _next_instance_id: int = 1


func _init(rng: RandomNumberGenerator = null) -> void:
	_rng = rng
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()


## Creates runtime instances from all members' owned cards and shuffles them together.
## The members' persistent decks are only read, never changed.
func build_from_party(party: Party) -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	for member in party.members:
		for owned in member.deck:
			var def := DataRegistry.get_card(owned.card_id)
			if def == null:
				continue
			draw_pile.append(CardInstance.from_owned(owned, def, _next_instance_id))
			_next_instance_id += 1
	_shuffle(draw_pile)
	piles_changed.emit()


## Draws up to `count` cards, reshuffling the discard pile when the draw pile runs dry.
## Cards drawn beyond MAX_HAND_SIZE go straight to the discard pile.
func draw(count: int) -> Array[CardInstance]:
	var drawn: Array[CardInstance] = []
	for i in count:
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			_reshuffle_discard_into_draw()
		var card: CardInstance = draw_pile.pop_back()
		if hand.size() >= MAX_HAND_SIZE:
			discard_pile.append(card)
			continue
		hand.append(card)
		drawn.append(card)
	piles_changed.emit()
	return drawn


## A fallen owner stops contributing: their cards leave the draw pile, hand and discard pile, so
## later draws and reshuffles only use the remaining characters' cards. Exhausted cards stay exhausted.
func set_owner_inactive(owner_id: String) -> void:
	for pile: Array[CardInstance] in [draw_pile, hand, discard_pile]:
		for card in pile.duplicate():
			if card.owner_character_id == owner_id:
				pile.erase(card)
				set_aside.append(card)
	piles_changed.emit()


func remove_from_hand(card: CardInstance) -> bool:
	var index := hand.find(card)
	if index == -1:
		return false
	hand.remove_at(index)
	return true


func send_to_discard(card: CardInstance) -> void:
	if not card.definition.token:  # tokens vanish instead
		discard_pile.append(card)
	piles_changed.emit()


func send_to_exhaust(card: CardInstance) -> void:
	if not card.definition.token:
		exhaust_pile.append(card)
	piles_changed.emit()


## End of turn: the hand goes to the discard pile, except Retain cards (they stay for next turn).
func discard_hand() -> void:
	var kept: Array[CardInstance] = []
	for card in hand:
		if card.definition.token:  # unplayed tokens fade at the end of the turn
			continue
		if card.retains():
			kept.append(card)
		else:
			discard_pile.append(card)
	hand = kept
	piles_changed.emit()


## Creates `count` temporary copies of a token card in the hand (owned by the card's owner).
## A full hand (MAX_HAND_SIZE) takes no more. Returns how many were added.
func add_tokens(def: CardDef, count: int) -> int:
	var added := 0
	for i in count:
		if hand.size() >= MAX_HAND_SIZE:
			break
		var card := CardInstance.new()
		card.instance_id = _next_instance_id
		_next_instance_id += 1
		card.definition = def
		card.owner_character_id = def.owner_character_id
		card.owned_uid = "token_%d" % card.instance_id
		hand.append(card)
		added += 1
	if added > 0:
		piles_changed.emit()
	return added


func get_total_card_count() -> int:
	return draw_pile.size() + hand.size() + discard_pile.size() + exhaust_pile.size() + set_aside.size()


func _reshuffle_discard_into_draw() -> void:
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	_shuffle(draw_pile)
	reshuffled.emit()


## Fisher-Yates shuffle driven by the injected RNG (seedable for tests).
func _shuffle(cards: Array[CardInstance]) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
