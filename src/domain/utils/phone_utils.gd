extends RefCounted

## Single Canonical Phone Normalization & Formatting Utility for Godot Desktop
## Complies with Phase 3.6 Architecture Consolidation Standard.

static func to_us_phone_digits(raw: String) -> String:
	var regex = RegEx.new()
	regex.compile("\\D")
	var digits = regex.sub(raw, "", true)
	if digits.length() > 10:
		return digits.right(10)
	return digits

static func format_us_phone(raw: String) -> String:
	var digits = to_us_phone_digits(raw)
	if digits.length() != 10:
		return raw.strip_edges()
	var area = digits.left(3)
	var prefix = digits.substr(3, 3)
	var line = digits.right(4)
	return "(" + area + ") " + prefix + "-" + line
