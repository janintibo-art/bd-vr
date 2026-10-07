extends Node3D

const LIBRARY_DATA := "res://data/library.json"
const COVER_TARGET_HEIGHT := 0.82
const COVER_TARGET_WIDTH := 0.58
const PAGE_TARGET_HEIGHT := 1.68
const PAGE_TARGET_WIDTH := 2.50

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
var import_dialog_open := false

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
var placeholder_cover: Texture2D

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
    if import_dialog_open:
        return

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
        if Input.is_action_just_pressed("back"):
            _start_import()

func _load_library() -> void:
    books.clear()
    var file := FileAccess.open(LIBRARY_DATA, FileAccess.READ)
    if file == null:
        push_error("Impossible de charger la bibliothèque BD VR")
        return

    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is Array:
        books = parsed.duplicate(true)

    for imported in LibraryStore.load_imports():
        if imported is Dictionary:
            _merge_import_record(imported)

func _merge_import_record(imported: Dictionary) -> int:
    var target_id := str(imported.get("base_id", imported.get("id", "")))
    for i in books.size():
        if str(books[i].get("id", "")) == target_id:
            var merged: Dictionary = books[i].duplicate(true)
            merged.merge(imported, true)
            merged["id"] = target_id
            books[i] = merged
            return i

    books.append(imported.duplicate(true))
    return books.size() - 1

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
            else:
                _start_import()

func _on_controller_axis(action_name: String, value: Vector2) -> void:
    if action_name != "primary" or import_dialog_open:
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

    cover_nodes.clear()
    cover_labels.clear()

    for i in books.size():
        var book: Dictionary = books[i]
        var card := Node3D.new()
        card.name = "Book_%s" % str(book.get("id", i))
        card.position = Vector3(0.0, 1.43, -2.84)
        library_root.add_child(card)

        var cover := Sprite3D.new()
        var cover_texture := _book_cover_texture(book)
        if cover_texture == null:
            cover_texture = _get_placeholder_cover()
        cover.texture = cover_texture
        _fit_cover(cover, cover_texture)
        card.add_child(cover)

        var title := _label(str(book.get("title", "BD")), 31, 0.0020)
        title.position = Vector3(0.0, -0.53, 0.04)
        title.width = 0.82 / title.pixel_size
        card.add_child(title)

        cover_nodes.append(card)
        cover_labels.append(title)

    info_label = _label("", 30, 0.00235)
    info_label.position = Vector3(0.0, 0.63, -2.78)
    info_label.width = 4.6
    info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    library_root.add_child(info_label)

    helper_label = _label("Joystick : choisir   •   Gâchette / A : lire   •   B / Menu : importer ZIP ou CBZ", 22, 0.0020)
    helper_label.modulate = Color(0.68, 0.73, 0.82)
    helper_label.position = Vector3(0.0, 0.40, -2.75)
    library_root.add_child(helper_label)

func _rebuild_library() -> void:
    if library_root != null and is_instance_valid(library_root):
        library_root.free()
    _build_library()
    _refresh_library()

func _build_reader() -> void:
    reader_root = Node3D.new()
    reader_root.name = "ReaderRoot"
    reader_root.visible = false
    add_child(reader_root)

    var backdrop := MeshInstance3D.new()
    var backdrop_mesh := QuadMesh.new()
    backdrop_mesh.size = Vector2(3.5, 2.40)
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
        info_label.text = "Aucune BD • B / Menu pour importer un ZIP ou CBZ"
        return

    for i in cover_nodes.size():
        var delta := _carousel_delta(i, selected_index, cover_nodes.size())
        var card := cover_nodes[i]
        card.visible = abs(delta) <= 3
        if not card.visible:
            continue

        var selected := i == selected_index
        card.position.x = float(delta) * 0.70
        card.position.z = -2.58 if selected else (-2.83 - 0.035 * abs(delta))
        card.scale = Vector3.ONE * (1.12 if selected else maxf(0.78, 0.92 - 0.045 * abs(delta)))
        cover_labels[i].modulate = Color.WHITE if selected else Color(0.55, 0.6, 0.7)

    var book: Dictionary = books[selected_index]
    var book_id := str(book.get("id", "book"))
    var saved_page := int(progress.get(book_id, 0))
    var page_count := int(book.get("page_count", 0))
    var subtitle := str(book.get("subtitle", ""))
    var resume := ""
    if saved_page > 0:
        resume = "  •  Reprendre page %d" % (saved_page + 1)
    var imported_badge := "  •  IMPORTÉE" if bool(book.get("imported", false)) else ""
    info_label.text = "%s — %s  •  %d planches%s%s" % [
        book.get("title", ""),
        subtitle,
        page_count,
        imported_badge,
        resume
    ]

func _carousel_delta(index: int, center: int, count: int) -> int:
    var delta := index - center
    if count > 1:
        var half := int(ceil(float(count) / 2.0))
        if delta > half:
            delta -= count
        elif delta < -half:
            delta += count
    return delta

func _open_selected_book() -> void:
    if books.is_empty():
        return
    current_book_index = selected_index
    var book: Dictionary = books[current_book_index]
    current_page_index = int(progress.get(str(book.get("id", "book")), 0))
    var pages := _current_pages()
    current_page_index = clampi(current_page_index, 0, maxi(pages.size() - 1, 0))
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
    var pages := _current_pages()
    if pages.is_empty():
        return
    if current_page_index < pages.size() - 1:
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

func _current_pages() -> Array:
    if current_book_index < 0 or current_book_index >= books.size():
        return []

    var book: Dictionary = books[current_book_index]
    if bool(book.get("imported", false)):
        var imported_pages = book.get("pages", [])
        return imported_pages if imported_pages is Array else []

    var previews = book.get("preview_pages", [])
    return previews if previews is Array else []

func _refresh_reader() -> void:
    var book: Dictionary = books[current_book_index]
    var pages := _current_pages()
    if pages.is_empty():
        page_sprite.texture = null
        reader_title.text = str(book.get("title", "BD"))
        reader_counter.text = "Aucune planche lisible dans cette archive"
        return

    current_page_index = clampi(current_page_index, 0, pages.size() - 1)
    var texture := ZipComicImporter.texture_from_page(pages[current_page_index])
    page_sprite.texture = texture

    if texture != null:
        var size := texture.get_size()
        page_sprite.pixel_size = minf(
            PAGE_TARGET_HEIGHT / maxf(size.y, 1.0),
            PAGE_TARGET_WIDTH / maxf(size.x, 1.0)
        )

    reader_title.text = "%s  —  %s" % [book.get("title", ""), book.get("subtitle", "")]

    if bool(book.get("imported", false)):
        reader_counter.text = "PAGE  %d / %d    •    ZIP / CBZ" % [current_page_index + 1, pages.size()]
    else:
        reader_counter.text = "APERÇU  %d / %d    •    BD complète : %d planches" % [
            current_page_index + 1,
            pages.size(),
            int(book.get("page_count", 0))
        ]

    if texture == null:
        reader_counter.text += "    •    SOURCE INACCESSIBLE : réimporte la BD"

func _save_current_progress() -> void:
    if current_book_index < 0 or current_book_index >= books.size():
        return
    var book: Dictionary = books[current_book_index]
    progress[str(book.get("id", "book"))] = current_page_index
    SaveManager.save_all(progress)

func _start_import() -> void:
    if import_dialog_open:
        return

    import_dialog_open = true
    info_label.text = "Ouverture du sélecteur… choisis un fichier ZIP ou CBZ"

    var filters := PackedStringArray([
        "*.zip,*.cbz;Bandes dessinées ZIP / CBZ;application/zip,application/x-zip-compressed,application/vnd.comicbook+zip"
    ])

    var err := DisplayServer.file_dialog_show(
        "Importer une BD",
        "",
        "",
        false,
        DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
        filters,
        Callable(self, "_on_import_dialog_result")
    )

    if err != OK:
        import_dialog_open = false
        info_label.text = "Le sélecteur de fichiers Android n'est pas disponible sur cet appareil."

func _on_import_dialog_result(status: bool, selected_paths: PackedStringArray, _selected_filter_index: int) -> void:
    import_dialog_open = false

    if not status or selected_paths.is_empty():
        _refresh_library()
        return

    var source_path := str(selected_paths[0])
    _persist_android_uri(source_path)

    var base_id := _guess_base_id(source_path)
    var import_id := base_id
    if import_id.is_empty():
        import_id = "import_%d_%d" % [int(Time.get_unix_time_from_system()), randi_range(1000, 9999)]

    var cache_dir := "user://bd_import_cache/%s" % import_id
    info_label.text = "Analyse de la BD…"

    var pages := ZipComicImporter.scan_pages(source_path, cache_dir)
    if pages.is_empty():
        info_label.text = "Aucune image PNG/JPG/WEBP trouvée dans ce ZIP/CBZ."
        return

    var record: Dictionary = {
        "id": import_id,
        "imported": true,
        "source_path": source_path,
        "pages": pages,
        "page_count": pages.size()
    }

    if not base_id.is_empty():
        record["base_id"] = base_id
        var builtin := _book_by_id(base_id)
        record["title"] = str(builtin.get("title", ZipComicImporter.display_name_from_path(source_path)))
        record["subtitle"] = str(builtin.get("subtitle", "ZIP / CBZ"))
    else:
        record["title"] = ZipComicImporter.display_name_from_path(source_path)
        record["subtitle"] = "BD importée • ZIP / CBZ"
        record["cover_page"] = pages[0]

    LibraryStore.upsert_import(record)
    _load_library()

    selected_index = 0
    for i in books.size():
        if str(books[i].get("id", "")) == import_id:
            selected_index = i
            break

    _rebuild_library()
    info_label.text = "%s importée • %d planches prêtes à lire" % [
        str(books[selected_index].get("title", "BD")),
        pages.size()
    ]

func _persist_android_uri(uri: String) -> void:
    if OS.get_name() != "Android" or not uri.begins_with("content://"):
        return

    var android_runtime = Engine.get_singleton("AndroidRuntime")
    if android_runtime != null:
        android_runtime.updatePersistableUriPermission(uri, true)

func _guess_base_id(source_path: String) -> String:
    var decoded := source_path.uri_decode().to_lower()
    for book in books:
        var book_id := str(book.get("id", ""))
        if bool(book.get("imported", false)):
            continue

        var source_hint := str(book.get("source_hint", "")).uri_decode().to_lower().get_basename()
        if source_hint.length() >= 4 and decoded.contains(source_hint.substr(0, 4)):
            return book_id

        var title := str(book.get("title", "")).to_lower()
        if title.length() >= 4 and decoded.contains(title.substr(0, 4)):
            return book_id

    return ""

func _book_by_id(book_id: String) -> Dictionary:
    for book in books:
        if str(book.get("id", "")) == book_id:
            return book
    return {}

func _book_cover_texture(book: Dictionary) -> Texture2D:
    var cover_path := str(book.get("cover", ""))
    if not cover_path.is_empty():
        var resource = load(cover_path)
        if resource is Texture2D:
            return resource

    var cover_page = book.get("cover_page", null)
    if cover_page != null:
        return ZipComicImporter.texture_from_page(cover_page)

    var pages = book.get("pages", [])
    if pages is Array and not pages.is_empty():
        return ZipComicImporter.texture_from_page(pages[0])

    return null

func _fit_cover(sprite: Sprite3D, texture: Texture2D) -> void:
    if texture == null:
        return
    var size := texture.get_size()
    sprite.pixel_size = minf(
        COVER_TARGET_HEIGHT / maxf(size.y, 1.0),
        COVER_TARGET_WIDTH / maxf(size.x, 1.0)
    )

func _get_placeholder_cover() -> Texture2D:
    if placeholder_cover != null:
        return placeholder_cover
    var image := Image.create(512, 720, false, Image.FORMAT_RGBA8)
    image.fill(Color(0.10, 0.12, 0.17, 1.0))
    placeholder_cover = ImageTexture.create_from_image(image)
    return placeholder_cover

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
