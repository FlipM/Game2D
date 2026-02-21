extends Resource

# Reference to the item's metadata/definition (ItemData resource)
@export var data = null
# Current stack size
@export var count: int = 1
# Container contents: Array of ItemInstance (only relevant when data.is_container == true)
@export var contents: Array = []
# Internal: parent container reference for anti-cycle traversal (not exported)
var parent_container = null


# --- Stacking ---

func can_stack_with(other) -> bool:
    return data != null and other != null and data == other.data and data.is_stackable

# Add up to `amount` to this stack. Returns how many were actually added.
func add_to_stack(amount: int) -> int:
    if not data or not data.is_stackable:
        return 0
    var room = data.max_stack - count
    var to_add = min(room, amount)
    count += to_add
    return to_add

# Remove up to `amount` from this stack. Returns how many were actually removed.
func remove_from_stack(amount: int) -> int:
    var taken = min(count, amount)
    count -= taken
    return taken

func is_full() -> bool:
    if data and data.is_stackable:
        return count >= data.max_stack
    return count >= 1

func is_empty() -> bool:
    return count <= 0


# --- Container / Anti-cycle logic ---

# `contents` is a fixed-length Array when the container has a slot limit, or a
# growable Array when container_slots == 0.  Empty slots are represented as null.
# This lets us have "first empty slot" semantics without a separate bookkeeping array.

# Returns true if `item` can be legally added to this container (capacity + cycle check).
func can_add_to_container(item) -> bool:
    if not data or not data.is_container:
        return false
    # Anti-cycle: walk ancestor chain, reject if `item` (or `item`'s data) already appears
    var visited = {}
    var curr = self
    while curr != null:
        if curr == item:
            return false
        visited[curr] = true
        curr = curr.parent_container
        if curr in visited:
            break
    # Capacity: unlimited containers always have room; slot-limited ones need a free slot.
    if data.container_slots > 0:
        return _find_placement_slot(item) != -2  # -2 = truly no room
    return true

# Place `item` into this container following the slot-placement rule:
#   1. If the top item in the first eligible slot is the same stackable type and not
#      full, merge into it.
#   2. Otherwise place into the first empty slot (null entry).
#   3. If the first eligible slot holds another container, recurse into it with the
#      same rule (depth-first).
# Stores the item BY REFERENCE (no duplicate). Returns true on success.
func add_to_container(item) -> bool:
    if not can_add_to_container(item):
        return false
    return _place_item(item)

# Internal: attempt to place `item` into this container. Returns true on success.
func _place_item(item) -> bool:
    var slots = data.container_slots  # 0 = unlimited

    # First pass: try to stack onto a matching top-level slot entry.
    for i in contents.size():
        var slot = contents[i]
        if slot == null:
            continue
        if slot.can_stack_with(item) and not slot.is_full():
            slot.add_to_stack(item.count)
            return true

    # Second pass: find the first empty (null) slot or append if unlimited.
    if slots == 0:
        # Unlimited — just append by reference.
        item.parent_container = self
        contents.append(item)
        return true
    else:
        # Fixed slots — ensure the array is the right length.
        while contents.size() < slots:
            contents.append(null)
        for i in contents.size():
            if contents[i] == null:
                item.parent_container = self
                contents[i] = item
                return true
        # No empty slot found — try recursing into any nested container slots.
        for i in contents.size():
            var slot = contents[i]
            if slot != null and slot.data and slot.data.is_container:
                if slot.add_to_container(item):
                    return true
        return false

# Remove and return the item at `idx` from this container. Returns null on failure.
func remove_from_container(idx: int):
    if not data or not data.is_container:
        return null
    if idx < 0 or idx >= contents.size():
        return null
    var removed = contents[idx]
    contents[idx] = null  # leave the slot empty rather than collapsing the array
    if removed != null:
        removed.parent_container = null
    return removed

# Internal helper: returns the index of the best placement slot, or -2 if no room.
# Used only for capacity pre-check in can_add_to_container.
# Pure read: does NOT mutate `contents`.
func _find_placement_slot(item) -> int:
    var slots = data.container_slots
    # Count existing slots without padding the array.
    var effective_size = max(contents.size(), slots)
    for i in effective_size:
        var slot = contents[i] if i < contents.size() else null
        if slot == null:
            return i
        if slot.can_stack_with(item) and not slot.is_full():
            return i
        if slot.data and slot.data.is_container and slot.can_add_to_container(item):
            return i
    return -2
