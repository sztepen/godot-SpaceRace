# GaneStateHandler is autoloaded
extends Node

signal new_stars_generated(game_state)
signal new_game_prepared

# imports
var GameState = preload("res://Scripts/Model/GameState.gd")
var Player = preload("res://Scripts/Model/Player.gd")
var Colony = preload("res://Scripts/Model/Colony.gd")

var GalaxyGenerator = preload("res://Scripts/Generator/GalaxyGenerator.gd")
var RaceGenerator = preload("res://Scripts/Generator/RaceGenerator.gd")
var ColonyGenerator = preload("res://Scripts/Generator/ColonyGenerator.gd")
# FIXME: temp for debug
var ColonyManager = preload("res://Scripts/Manager/ColonyManager.gd")
var KnowledgeFactory = preload("res://Scripts/Factories/KnowledgeFactory.gd")
onready var ColonyController = Classes.model["ColonyController"]

var GameStatePurger = preload("res://Scripts/Tools/GameStatePurger.gd")
var GameStateTransformer = preload("res://Scripts/Transformer/GameStateTransformer.gd")
# temporary game state for the "new game" screen
var new_game_state

# current game state after loading or starting
# TODO: auto-save after every action
var game_state

# Save stuff
# TODO: saving and loading is responsibility of something else
var saveable_state = {}
var save_path = "user://savegame.sav"

func _ready():
	pass

# this loads the resume savegame or initializes a default game state
func get_most_current_game_state():
	if File.new().file_exists("user://resume.sav"):
		game_state = load_old_game("user://resume.sav")
	else:
		game_state = start_new_game()
	return game_state

# TODO: implement resuming
func load_old_game(path):
	return start_new_game()

# start new default game
# this is also what happens when you resume without a resume state
func start_new_game():
	#randomize()
	#purge_game_state(game_state)
	generate_stars(mapdefs.default_galaxy_settings.galaxy_size)
	initialize_galaxy(mapdefs.default_galaxy_settings, "minions", mapdefs.galaxy_colors.GREEN)
	#print(inst2dict(game_state))
	return game_state

# get a default game state, don't assign it to anything
func make_game_state(settings):
	var gs = GameState.new()
	gs.galaxy_settings.galaxy_size = settings.galaxy_size
	gs.galaxy_settings.atmosphere = settings.atmosphere
	gs.galaxy_settings.races = settings.races
	return gs

# this creates a galaxy that can be displayed on the "new game" screen
# and keeps it in new_game_state
func generate_stars(size = null):
	if new_game_state != null:
		GameStatePurger.purge_game_state(new_game_state)
	new_game_state = make_game_state(mapdefs.default_galaxy_settings)
	new_game_state.galaxy = GalaxyGenerator.generate_stars(size)
	emit_signal("new_stars_generated", new_game_state)
	pass
	
# this takes the existing prepared galaxy (from new_game_state)
# applies the options from the settings screen
# and initializes a proper game state
func initialize_galaxy(galaxy_options, race_key, color):
	if new_game_state:
		# fill temp galaxy with planets
		GalaxyGenerator.generate_star_systems(new_game_state.galaxy)
		GalaxyGenerator.connect_star_systems(new_game_state.galaxy)
		#print(new_game_state.galaxy.lanes)
		
		# initialize the navigator
		GalaxyNavigator.get_astar_from_galaxy(new_game_state.galaxy)

		# initialize player race
		var player = RaceGenerator.generate_player(new_game_state, race_key)
		player.color = color
		new_game_state.races[race_key] = player
		new_game_state.human_player = player

		# pick & initialize the rest of the races
		var num_races = galaxy_options.races
		var all_races = RaceDefinitions.races
		var other_races = []
		var occupied_systems = []
		while other_races.size() < num_races-1:
			var index = randi() % all_races.size()
			var picked = all_races[index]
			if not picked == race_key and not picked in other_races:
				other_races.append(picked)
		for other_race in other_races:
			var alien = RaceGenerator.generate_player(new_game_state, other_race)
			alien.type = "ai"
			new_game_state.races[other_race] = alien
			
		for r_key in new_game_state.races:
			var participant = new_game_state.races[r_key]
			# scatter the starter colonies
			# plunk the players onto ANY planet in not yet occupied systems
			var random_system = Utils.rand_pick_from_array(new_game_state.galaxy.systems)
			while random_system in occupied_systems:
				random_system = Utils.rand_pick_from_array(new_game_state.galaxy.systems)

			occupied_systems.append(random_system)
			var planet = Utils.rand_pick_from_array(random_system.planets)

			# give the planet a colony base
			# FIXME: meeeeeeeeh?
			# home = true
			ColonyGenerator.initialize_colony(participant, planet, true)
			# FIXME: remove this sometime or make it DEBUG-conditional
			if participant == player and true:
				player.completed_research = ["orbital_structures", "xenobiology", "environmental_encapsulation", "interplanetary_exploration", "tonklin_diary", "spacetime_surfing"]
				planet.base_population += 20
				planet.population.slots += 20
				planet.population.free = planet.population.slots - planet.population.alive
				
				for i in range(planet.population.free):
					var build_next = ColonyManager.manage(planet.colony)
					if build_next != null:
						if build_next.project != null:
							ColonyController.start_project(planet.colony, build_next.square, [build_next.project, build_next.type])
							ColonyController.finish_project(planet.colony)
							ColonyController.grow_population(planet.colony)
				ColonyController.grow_population(planet.colony)
				ColonyController.grow_population(planet.colony)


			#new_game_state.galaxy.races = new_game_state.races
		for r_key in new_game_state.races:
			var participant = new_game_state.races[r_key]
			#KnowledgeFactory.initialize_player_knowledge(participant, new_game_state)

		# move everything into the normal game state
		if game_state != null:
			GameStatePurger.purge_game_state(game_state)
			game_state = null
		game_state = new_game_state
		#GameStatePurger.purge_game_state(new_game_state)
		new_game_state = null
	pass

func save_game_state(save_name = null):
	var path = save_path
	if save_name != null:
		path = save_name
	saveable_state.turn = game_state.turn
	saveable_state.galaxy = game_state.galaxy
	saveable_state.difficulty = game_state.difficulty
	saveable_state.races = game_state.races
	
	var file = File.new()
	if file.open(path, File.WRITE) != 0:
		print("Error opening save")
	
	file.store_line(saveable_state.to_json())
	file.close()
	pass

func load_game_state(save_name = null):
	game_state.turn = saveable_state.turn
	game_state.galaxy = saveable_state.galaxy
	game_state.difficulty = saveable_state.difficulty
	game_state.races = saveable_state.races
	pass
