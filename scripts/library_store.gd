class_name LibraryStore
extends RefCounted

const IMPORTS_PATH := "user://bd_vr_imports.json"

static func load_imports() -> Array:
    if not FileAccess.file_exists(IMPORTS_PATH):
        return []

    var file := FileAccess.open(IMPORTS_PATH, FileAccess.READ)
    if file == null:
        return []

    var parsed = JSON.parse_string(file.get_as_text())
    return parsed if parsed is Array else []

static func save_imports(imports: Array) -> void:
    var file := FileAccess.open(IMPORTS_PATH, FileAccess.WRITE)
    if file == null:
        return
    file.store_string(JSON.stringify(imports, "  "))

static func upsert_import(record: Dictionary) -> void:
    var imports := load_imports()
    var record_id := str(record.get("id", ""))
    var replaced := false

    for i in imports.size():
        if imports[i] is Dictionary and str(imports[i].get("id", "")) == record_id:
            imports[i] = record.duplicate(true)
            replaced = true
            break

    if not replaced:
        imports.append(record.duplicate(true))

    save_imports(imports)
