class_name ZipComicImporter
extends RefCounted

const IMAGE_EXTENSIONS := [".png", ".jpg", ".jpeg", ".webp"]
const ARCHIVE_EXTENSIONS := [".zip", ".cbz"]
const IGNORE_HINTS := [
    "/couverture",
    "/couvertures",
    "/cover",
    "/covers",
    "/personnage",
    "/personnages",
    "/character",
    "/characters",
    "/avatar",
    "/avatars",
    "/logo",
    "/logos",
    "/icone",
    "/icones",
    "/icon",
    "/icons",
    "/thumb",
    "/thumbnail"
]

static func scan_pages(zip_path: String, cache_dir: String = "") -> Array:
    var index := _scan_archive(zip_path)
    var preferred: Array = index.get("preferred", [])
    var all_images: Array = index.get("all_images", [])
    var nested: Array = index.get("nested", [])

    # Si l'archive contient déjà de vraies planches, on ne parcourt pas les ZIP
    # imbriqués afin d'éviter les doublons (cas d'Arthéus).
    if not preferred.is_empty():
        return preferred

    # Si seules des couvertures/personnages sont directement présents, on tente
    # d'abord les archives imbriquées (épisodes/tomes).
    if not nested.is_empty() and not cache_dir.is_empty():
        var nested_pages := _scan_nested_archives(zip_path, nested, cache_dir)
        if not nested_pages.is_empty():
            return nested_pages

    # Dernier recours : accepter les images ignorées si l'archive ne contient
    # rien d'autre.
    return all_images

static func list_pages(zip_path: String) -> PackedStringArray:
    var result := PackedStringArray()
    for page in scan_pages(zip_path):
        if page is Dictionary:
            result.append(str(page.get("entry", "")))
    return result

static func texture_from_page(page) -> Texture2D:
    if page is String:
        var resource = load(page)
        return resource if resource is Texture2D else null

    if page is Dictionary:
        var archive := str(page.get("archive", ""))
        var entry := str(page.get("entry", ""))
        if not archive.is_empty() and not entry.is_empty():
            return texture_from_zip(archive, entry)

    return null

static func texture_from_zip(zip_path: String, entry: String) -> Texture2D:
    var reader := ZIPReader.new()
    if reader.open(zip_path) != OK:
        return null

    var bytes := reader.read_file(entry)
    reader.close()
    if bytes.is_empty():
        return null

    var image := Image.new()
    var lower := entry.to_lower()
    var err := ERR_FILE_UNRECOGNIZED

    if lower.ends_with(".png"):
        err = image.load_png_from_buffer(bytes)
    elif lower.ends_with(".jpg") or lower.ends_with(".jpeg"):
        err = image.load_jpg_from_buffer(bytes)
    elif lower.ends_with(".webp"):
        err = image.load_webp_from_buffer(bytes)

    if err != OK:
        return null

    return ImageTexture.create_from_image(image)

static func display_name_from_path(path: String) -> String:
    var decoded := path.uri_decode()
    var filename := decoded.get_file()
    var title := filename.get_basename()
    title = title.replace("_", " ").replace("-", " ").strip_edges()
    if title.is_empty():
        return "BD importée"
    return title

static func _scan_archive(archive_path: String) -> Dictionary:
    var preferred: Array = []
    var all_images: Array = []
    var nested: Array = []

    var reader := ZIPReader.new()
    if reader.open(archive_path) != OK:
        return {
            "preferred": preferred,
            "all_images": all_images,
            "nested": nested
        }

    var entries := reader.get_files()
    entries.sort_custom(_natural_less)

    for entry in entries:
        var lower := entry.to_lower()

        if _has_extension(lower, IMAGE_EXTENSIONS):
            var page := {
                "archive": archive_path,
                "entry": entry
            }
            all_images.append(page)
            if not _is_ignored_path(lower):
                preferred.append(page)

        elif _has_extension(lower, ARCHIVE_EXTENSIONS):
            if not _is_ignored_path(lower):
                nested.append(entry)

    reader.close()

    return {
        "preferred": preferred,
        "all_images": all_images,
        "nested": nested
    }

static func _scan_nested_archives(source_archive: String, nested_entries: Array, cache_dir: String) -> Array:
    var result: Array = []
    var absolute_cache := ProjectSettings.globalize_path(cache_dir)
    DirAccess.make_dir_recursive_absolute(absolute_cache)

    var counter := 0
    for entry in nested_entries:
        var nested_path := cache_dir.path_join("nested_%03d.zip" % counter)
        counter += 1

        if not _extract_nested_archive(source_archive, str(entry), nested_path):
            continue

        var nested_index := _scan_archive(nested_path)
        var preferred: Array = nested_index.get("preferred", [])
        if not preferred.is_empty():
            result.append_array(preferred)
        else:
            var all_images: Array = nested_index.get("all_images", [])
            if not all_images.is_empty():
                result.append_array(all_images)

    return result

static func _extract_nested_archive(source_archive: String, entry: String, destination: String) -> bool:
    var reader := ZIPReader.new()
    if reader.open(source_archive) != OK:
        return false

    var bytes := reader.read_file(entry)
    reader.close()

    if bytes.is_empty():
        return false

    var file := FileAccess.open(destination, FileAccess.WRITE)
    if file == null:
        return false

    file.store_buffer(bytes)
    return true

static func _has_extension(path: String, extensions: Array) -> bool:
    for extension in extensions:
        if path.ends_with(str(extension)):
            return true
    return false

static func _is_ignored_path(path: String) -> bool:
    var normalized := "/" + path.to_lower().replace("\\", "/")
    for hint in IGNORE_HINTS:
        if normalized.contains(str(hint)):
            return true
    return false

static func _natural_less(a: String, b: String) -> bool:
    return a.naturalnocasecmp_to(b) < 0
