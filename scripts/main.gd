extends Node3D

const LIBRARY_DATA := "res://data/library.json"
const COVER_PIXEL_SIZE := 0.00084
const PAGE_TARGET_HEIGHT := 1.58

@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_controller: XRController3D = $XROrigin3D/LeftController
@onready var right_controller: XRController3D = $XROrigin3D/RightController
@onready var desktop_camera: Camera3D = $DesktopCamera

var books: Array = []
var selected_index := 0
var current_book_index := 0
var current_page_index := 0
var reading := false
var progress: Dictionary = {}

var library_root: Node3D
var reader_root: Node3D
var cover_nodes: Array[Node3D] = []
var cover_labels: Array[Label3D] = []
var page_sprite: Sprite3D
var reader_title: Label3D
var reader_counter: Label3D
var helper_label: Label3D
var header_label: Label3D
var subheader_label: Label3D
var info_label: Label3D
var thumbstick_armed := true

func _ready() -> void:
    _load_library()
    _load_progress()
    _initialize_xr()
    _build_room()
    _build_library()
    _build_reader()
    _connect_controllers()
    _refresh_library()

func _process(_delta: float) -> void:
    if reading:
        if Input.is_action_just_pressed("next_item"):
            _next_page()
        if Input.is_action_just_pressed("previous_item"):
            _previous_page()
        if Input.is_action_just_pressed("open_item"):
            _next_page()
        if Input.is_action_just_pressed("back"):
            _close_reader()
    else:
        if Input.is_action_just_pressed("next_item"):
            _move_selection(1)
        if Input.is_action_just_pressed("previous_item"):
            _move_selection(-1)
        if Input.is_action_just_pressed("open_item"):
            _open_selected_book()

func _load_library() -> void:
    var file := FileAccess.open(LIBRARY_DATA, FileAccess.READ)
    if file == null:
        push_error("Impossible de charger la bibliothèque BD VR")
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is Array:
        books = parsed

func _load_progress() -> void:
    progress = SaveManager.load_all()

func _initialize_xr() -> void:
    var xr_interface := XRServer.find_interface("OpenXR")
    if xr_interface != null and xr_interface.initialize():
        get_viewport().use_xr = true
        desktop_camera.current = false
    else:
        get_viewport().use_xr = false
        desktop_camera.current = true

func _connect_controllers() -> void:
    left_controller.button_pressed.connect(_on_controller_button)
    right_controller.button_pressed.connect(_on_controller_button)
    left_controller.input_vector2_changed.connect(_on_controller_axis)
    right_controller.input_vector2_changed.connect(_on_controller_axis)

func _on_controller_button(action_name: String) -> void:
    match action_name:
        "trigger_click", "ax_button":
            if reading:
                _next_page()
            else:
                _open_selected_book()
        "by_button", "menu_button":
            if reading:
                _close_reader()

func _on_controller_axis(action_name: String, value: Vector2) -> void:
    if action_name != "primary":
        return
    if abs(value.x) < 0.45:
        thumbstick_armed = true
        return
    if not thumbstick_armed:
        return
    thumbstick_armed = false
    if reading:
        if value.x > 0.0:
            _next_page()
        else:
            _previous_page()
    else:
        _move_selection(1 if value.x > 0.0 else -1)

func _build_room() -> void:
    var env := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.012, 0.016, 0.024)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.24, 0.28, 0.36)
    environment.ambient_light_energy = 0.42
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.environment = environment
    add_child(env)

    var floor := MeshInstance3D.new()
    var floor_mesh := PlaneMesh.new()
    floor_mesh.size = Vector2(10.0, 10.0)
    floor.mesh = floor_mesh
    floor.material_override = _material(Color(0.035, 0.041, 0.052), 0.9)
    add_child(floor)

    var wall := MeshInstance3D.new()
    var wall_mesh := BoxMesh.new()
    wall_mesh.size = Vector3(5.6, 2.8, 0.08)
    wall.mesh = wall_mesh
    wall.position = Vector3(0.0, 1.45, -3.28)
    wall.material_override = _material(Color(0.055, 0.062, 0.079), 0.82)
    add_child(wall)

    for y in [0.62, 1.38, 2.14]:
        var shelf := MeshInstance3D.new()
        var shelf_mesh := BoxMesh.new()
        shelf_mesh.size = Vector3(5.0, 0.055, 0.32)
        shelf.mesh = shelf_mesh
        shelf.position = Vector3(0.0, y, -3.05)
        shelf.material_override = _material(Color(0.11, 0.075, 0.052), 0.72)
        add_child(shelf)

    var key_light := OmniLight3D.new()
    key_light.position = Vector3(0.0, 2.65, -1.2)
    key_light.light_energy = 1.9
    key_light.omni_range = 5.0
    key_light.light_color = Color(0.86, 0.91, 1.0)
    add_child(key_light)

    var warm_light := OmniLight3D.new()
    warm_light.position = Vector3(-2.0, 1.8, -2.2)
    warm_light.light_energy = 0.7
    warm_light.omni_range = 3.0
    warm_light.light_color = Color(1.0, 0.78, 0.55)
    add_child(warm_light)

func _build_library() -> void:
    library_root = Node3D.new()
    library_root.name = "LibraryRoot"
    add_child(library_root)

    header_label = _label("BD VR", 76, 0.0032)
    header_label.position = Vector3(0.0, 2.34, -3.0)
    library_root.add_child(header_label)

    subheader_label = _label("Ta bibliothèque immersive • Quest 3", 28, 0.0024)
    subheader_label.modulate = Color(0.72, 0.78, 0.9)
    subheader_label.position = Vector3(0.0, 2.12, -3.0)
    library_root.add_child(subheader_label)

    var count := books.size()
    for i in count:
        var book: Dictionary = books[i]
        var card := Node3D.new()
        card.name = "Book_%s" % book.get("id", str(i))
        var x := (float(i) - float(count - 1) * 0.5) * 0.68
        card.position = Vector3(x, 1.43, -2.84)
        library_root.add_child(card)

        var cover := Sprite3D.new()
        cover.texture = load(str(book.get("cover", "")))
        cover.pixel_size = COVER_PIXEL_SIZE
        cover.position = Vector3(0.0, 0.0, 0.0)
        card.add_child(cover)

        var title := _label(str(book.get("title", "BD")), 34, 0.0021)
        title.position = Vector3(0.0, -0.53, 0.04)
        card.add_child(title)

        cover_nodes.append(card)
        cover_labels.append(title)

    info_label = _label("", 30, 0.00235)
    info_label.position = Vector3(0.0, 0.63, -2.78)
    info_label.width = 4.4
    info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    library_root.add_child(info_label)

    helper_label = _label("Joystick : choisir   •   Gâchette / A : lire", 24, 0.0021)
    helper_label.modulate = Color(0.68, 0.73, 0.82)
    helper_label.position = Vector3(0.0, 0.42, -2.75)
    library_root.add_child(helper_label)

func _build_reader() -> void:
    reader_root = Node3D.new()
    reader_root.name = "ReaderRoot"
    reader_root.visible = false
    add_child(reader_root)

    var backdrop := MeshInstance3D.new()
    var backdrop_mesh := QuadMesh.new()
    backdrop_mesh.size = Vector2(3.4, 2.35)
    backdrop.mesh = backdrop_mesh
    backdrop.position = Vector3(0.0, 1.45, -2.92)
    backdrop.material_override = _material(Color(0.008, 0.01, 0.014), 0.9)
    reader_root.add_child(backdrop)

    page_sprite = Sprite3D.new()
    page_sprite.position = Vector3(0.0, 1.48, -2.62)
    reader_root.add_child(page_sprite)

    reader_title = _label("", 30, 0.00225)
    reader_title.position = Vector3(0.0, 2.38, -2.57)
    reader_root.add_child(reader_title)

    reader_counter = _label("", 24, 0.00215)
    reader_counter.position = Vector3(0.0, 0.48, -2.55)
    reader_counter.modulate = Color(0.75, 0.8, 0.9)
    reader_root.add_child(reader_counter)

    var reader_help := _label("← / → : pages   •   Gâchette / A : suivante   •   B / Menu : bibliothèque", 20, 0.00195)
    reader_help.position = Vector3(0.0, 0.30, -2.55)
    reader_help.modulate = Color(0.58, 0.64, 0.73)
    reader_root.add_child(reader_help)

func _move_selection(delta: int) -> void:
    if books.is_empty():
        return
    selected_index = posmod(selected_index + delta, books.size())
    _refresh_library()

func _refresh_library() -> void:
    if books.is_empty():
        return
    for i in cover_nodes.size():
        var card := cover_nodes[i]
        var selected := i == selected_index
        card.scale = Vector3.ONE * (1.10 if selected else 0.90)
        card.position.z = -2.62 if selected else -2.84
        cover_labels[i].modulate = Color.WHITE if selected else Color(0.55, 0.6, 0.7)

    var book: Dictionary = books[selected_index]
    var book_id := str(book.get("id", "book"))
    var saved_page := int(progress.get(book_id, 0))
    var page_count := int(book.get("page_count", 0))
    var subtitle := str(book.get("subtitle", ""))
    var resume := ""
    if saved_page > 0:
        resume = "  •  Reprendre aperçu page %d" % (saved_page + 1)
    info_label.text = "%s — %s  •  %d planches%s" % [book.get("title", ""), subtitle, page_count, resume]

func _open_selected_book() -> void:
    if books.is_empty():
        return
    current_book_index = selected_index
    var book: Dictionary = books[current_book_index]
    current_page_index = int(progress.get(str(book.get("id", "book")), 0))
    var previews: Array = book.get("preview_pages", [])
    current_page_index = clampi(current_page_index, 0, maxi(previews.size() - 1, 0))
    reading = true
    library_root.visible = false
    reader_root.visible = true
    _refresh_reader()

func _close_reader() -> void:
    _save_current_progress()
    reading = false
    reader_root.visible = false
    library_root.visible = true
    _refresh_library()

func _next_page() -> void:
    var previews := _current_preview_pages()
    if previews.is_empty():
        return
    if current_page_index < previews.size() - 1:
        current_page_index += 1
        _save_current_progress()
        _refresh_reader()
    else:
        _close_reader()

func _previous_page() -> void:
    if current_page_index > 0:
        current_page_index -= 1
        _save_current_progress()
        _refresh_reader()

func _current_preview_pages() -> Array:
    if current_book_index < 0 or current_book_index >= books.size():
        return []
    var book: Dictionary = books[current_book_index]
    return book.get("preview_pages", [])

func _refresh_reader() -> void:
    var book: Dictionary = books[current_book_index]
    var previews := _current_preview_pages()
    if previews.is_empty():
        page_sprite.texture = null
        return

    current_page_index = clampi(current_page_index, 0, previews.size() - 1)
    var texture: Texture2D = load(str(previews[current_page_index]))
    page_sprite.texture = texture
    if texture != null:
        var size := texture.get_size()
        var pixel_size := PAGE_TARGET_HEIGHT / maxf(size.y, 1.0)
        if size.x > size.y:
            pixel_size = minf(pixel_size, 2.25 / maxf(size.x, 1.0))
        page_sprite.pixel_size = pixel_size

    reader_title.text = "%s  —  %s" % [book.get("title", ""), book.get("subtitle", "")]
    reader_counter.text = "APERÇU  %d / %d    •    BD complète : %d planches" % [current_page_index + 1, previews.size(), int(book.get("page_count", 0))]

func _save_current_progress() -> void:
    if current_book_index < 0 or current_book_index >= books.size():
        return
    var book: Dictionary = books[current_book_index]
    progress[str(book.get("id", "book"))] = current_page_index
    SaveManager.save_all(progress)

func _label(text_value: String, size: int, px: float) -> Label3D:
    var label := Label3D.new()
    label.text = text_value
    label.font_size = size
    label.pixel_size = px
    label.outline_size = 8
    label.outline_modulate = Color(0.0, 0.0, 0.0, 0.82)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.no_depth_test = true
    return label

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material
