extends SceneTree
## Headless smoke test: plays a few full customer groups through the whole loop.
## Run: godot --headless -s tests/smoke_test.gd

func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.S = main._fresh()
	main._new_group()
	var ok := true
	for g in 6:
		main._on_start()
		assert(main.phase == "session")
		var guard := 0
		while main.phase == "session" and guard < 100:
			main._step()
			guard += 1
			if main.group.hint_req:
				main._on_hint()
		if main.phase != "review":
			push_error("group %d did not reach review" % g); ok = false; break
		main._begin_reset()
		for n in main.mess_nodes.duplicate():
			main._on_mess(n)
		for i in main.chain():
			if main.S.broken.has(i):
				main._on_slot(i)
		if main.phase != "lobby":
			push_error("group %d stuck in %s" % [g, main.phase]); ok = false; break
		print("group %d ok: day %d cash %d rating %s" % [g, main.S.day, main.S.cash, main.avg_rating()])
	# buying: cycle slot 3 until something is placed
	main.S.cash = 1000
	main._on_slot(3)
	print("slot 3 now: ", main.S.slots[3], " cash ", main.S.cash)
	print("SMOKE TEST ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
