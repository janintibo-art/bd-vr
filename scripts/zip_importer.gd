class_name ZipComicImporter
extends RefCounted

const IMAGE_EXTENSIONS := [".png", ".jpg", ".jpeg", ".webp"]

static func list_pages(zip_path: String) -> PackedStringArray:
    var reader := ZIPReader.new()
    var result := PackedStringArray()
    if reader.open(zip_path) != OK:
        return result
    for entry in reader.get_files():
        var lower := entry.to_lower()
        for ext in IMAGE_EXTENSIONS:
            if lower.ends_with(ext):
                result.append(entry)
                break
    reader.close()
    result.sort_custom(_natural_less)
    return result

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

static func _natural_less(a: String, b: String) -> bool:
    var ra := RegEx.new()
    ra.compile("(\\d+)")
    var ma := ra.search(a.get_file())
    var mb := ra.search(b.get_file())
    if ma != null and mb != null:
        var na := int(ma.get_string(1))
        var nb := int(mb.get_string(1))
        if na != nb:
            return na < nb
    return a.naturalnocasecmp_to(b) < 0
