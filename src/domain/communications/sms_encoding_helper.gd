class_name SMSEncodingHelper
extends RefCounted

## SMS Encoding, Segmentation & Cost Estimation Helper
## Complies with 3GPP TS 23.038 / GSM 03.38 standard and Twilio SMS/MMS pricing rules.

# GSM-7 Basic Character Set (Codepoints)
# Standard 128 characters (0x00 to 0x7F mapping)
const GSM7_BASIC_CODEPOINTS: Array[int] = [
	0x0040, 0x00A3, 0x0024, 0x00A5, 0x00E8, 0x00E9, 0x00F9, 0x00EC, # @ £ $ ¥ è é ù ì
	0x00F2, 0x00C7, 0x000A, 0x00D8, 0x00F8, 0x000D, 0x00C5, 0x00E5, # ò Ç \n Ø ø \r Å å
	0x0394, 0x005F, 0x03A6, 0x0393, 0x039B, 0x03A9, 0x03A0, 0x03A8, # Δ _ Φ Γ Λ Ω Π Ψ
	0x03A3, 0x0398, 0x039E, 0x001B, 0x00C6, 0x00E6, 0x00DF, 0x00C9, # Σ Θ Ξ ESC Æ æ ß É
	0x0020, 0x0021, 0x0022, 0x0023, 0x00A4, 0x0025, 0x0026, 0x0027, # SP ! " # ¤ % & '
	0x0028, 0x0029, 0x002A, 0x002B, 0x002C, 0x002D, 0x002E, 0x002F, # ( ) * + , - . /
	0x0030, 0x0031, 0x0032, 0x0033, 0x0034, 0x0035, 0x0036, 0x0037, # 0 1 2 3 4 5 6 7
	0x0038, 0x0039, 0x003A, 0x003B, 0x003C, 0x003D, 0x003E, 0x003F, # 8 9 : ; < = > ?
	0x00A1, 0x0041, 0x0042, 0x0043, 0x0044, 0x0045, 0x0046, 0x0047, # ¡ A B C D E F G
	0x0048, 0x0049, 0x004A, 0x004B, 0x004C, 0x004D, 0x004E, 0x004F, # H I J K L M N O
	0x0050, 0x0051, 0x0052, 0x0053, 0x0054, 0x0055, 0x0056, 0x0057, # P Q R S T U V W
	0x0058, 0x0059, 0x005A, 0x00C4, 0x00D6, 0x00D1, 0x00DC, 0x00A7, # X Y Z Ä Ö Ñ Ü §
	0x00BF, 0x0061, 0x0062, 0x0063, 0x0064, 0x0065, 0x0066, 0x0067, # ¿ a b c d e f g
	0x0068, 0x0069, 0x006A, 0x006B, 0x006C, 0x006D, 0x006E, 0x006F, # h i j k l m n o
	0x0070, 0x0071, 0x0072, 0x0073, 0x0074, 0x0075, 0x0076, 0x0077, # p q r s t u v w
	0x0078, 0x0079, 0x007A, 0x00E4, 0x00F6, 0x00F1, 0x00FC, 0x00E0  # x y z ä ö ñ ü à
]

# GSM-7 Extended Characters (Each requires 2 septets / ESC prefix)
# ^, {, }, \, [, ~, ], |, €
const GSM7_EXTENDED_CODEPOINTS: Array[int] = [
	0x005E, # ^
	0x007B, # {
	0x007D, # }
	0x005C, # \
	0x005B, # [
	0x007E, # ~
	0x005D, # ]
	0x007C, # |
	0x20AC  # €
]

# Twilio rates & carrier fees derived from actual October 2026 usage audit:
# Outbound SMS: $0.0079 Twilio base + $0.0043 carrier fee = $0.0122 / segment
# Outbound MMS: $0.0200 Twilio base + $0.0080 carrier fee = $0.0280 / MMS unit
const COST_PER_SMS_SEGMENT: float = 0.0122
const COST_PER_MMS_MESSAGE: float = 0.0280

# Safe Unicode substitutions to GSM-7
const SAFE_SUBSTITUTIONS: Dictionary = {
	# Quotation marks
	"‘": "'", "’": "'", "‚": "'", "‛": "'",
	"“": "\"", "”": "\"", "„": "\"", "‟": "\"",
	"«": "\"", "»": "\"",
	# Dashes and hyphens
	"—": "-", # Em dash
	"–": "-", # En dash
	"―": "-", # Horizontal bar
	"−": "-", # Minus sign
	"‐": "-", # Hyphen
	"‑": "-", # Non-breaking hyphen
	# Spaces & whitespace
	"\u00A0": " ", # Non-breaking space
	"\u2002": " ", # En space
	"\u2003": " ", # Em space
	"\u2009": " ", # Thin space
	"\u202F": " ", # Narrow no-break space
	"\t": " ",     # Tab character
	# Bullets and middle dots
	"•": "-", "·": "-", "▪": "-", "▸": "-",
	# Ellipsis
	"…": "..."
}

static func is_gsm7_basic(cp: int) -> bool:
	return cp in GSM7_BASIC_CODEPOINTS

static func is_gsm7_extended(cp: int) -> bool:
	return cp in GSM7_EXTENDED_CODEPOINTS

## Full analysis of message text, segmentation, encoding, and cost
static func analyze_sms(text: String, has_media: bool = false, recipient_count: int = 1) -> Dictionary:
	var recips = maxi(0, recipient_count)
	
	if has_media:
		# MMS Mode: 1 flat MMS message per recipient regardless of length (up to 1600 chars)
		var mms_units = recips
		var est_cost = float(mms_units) * COST_PER_MMS_MESSAGE
		return {
			"encoding": "MMS",
			"is_mms": true,
			"char_count": text.length(),
			"segments_per_recipient": 1,
			"recipient_count": recips,
			"total_billable_units": mms_units,
			"unit_name": "MMS message" if mms_units == 1 else "MMS messages",
			"estimated_cost": est_cost,
			"rate_detail": "$0.0200 Twilio + $0.0080 carrier fee per MMS",
			"non_gsm_characters": [],
			"can_optimize": false,
			"summary_text": "%d recipient%s • MMS Attachment • Est. %d unit%s • $%.2f" % [
				recips, ("s" if recips != 1 else ""),
				mms_units, ("s" if mms_units != 1 else ""),
				est_cost
			]
		}
	
	var length = text.length()
	if length == 0:
		return {
			"encoding": "GSM-7",
			"is_mms": false,
			"char_count": 0,
			"segments_per_recipient": 0,
			"recipient_count": recips,
			"total_billable_units": 0,
			"unit_name": "SMS segments",
			"estimated_cost": 0.0,
			"rate_detail": "$0.0079 Twilio + ~$0.0043 carrier fee per segment",
			"non_gsm_characters": [],
			"can_optimize": false,
			"summary_text": "0 characters • 0 SMS segments"
		}

	var non_gsm_chars: Array[Dictionary] = []
	var non_gsm_map: Dictionary = {}
	var has_unicode: bool = false
	var gsm_extended_count: int = 0
	var utf16_units: int = 0

	for i in range(length):
		var cp = text.unicode_at(i)
		var ch = text[i]

		# In UTF-16, codepoints >= 0x10000 (such as emojis) require 2 code units (surrogate pair)
		var u16_len = 2 if cp >= 0x10000 else 1
		utf16_units += u16_len

		if is_gsm7_basic(cp):
			pass
		elif is_gsm7_extended(cp):
			gsm_extended_count += 1
		else:
			has_unicode = true
			if non_gsm_map.has(ch):
				non_gsm_map[ch]["count"] += 1
			else:
				var is_emoji = (cp >= 0x1F000 and cp <= 0x1FFFF) or (cp >= 0x2600 and cp <= 0x27BF) or (cp >= 0xFE00 and cp <= 0xFE0F)
				var entry = {
					"char": ch,
					"codepoint": "U+%04X" % cp,
					"count": 1,
					"is_emoji": is_emoji,
					"has_safe_replacement": SAFE_SUBSTITUTIONS.has(ch)
				}
				non_gsm_map[ch] = entry
				non_gsm_chars.append(entry)

	var segs_per_recip = 0
	var encoding_name = ""

	if has_unicode:
		encoding_name = "Unicode"
		# Unicode Segmentation:
		# Single segment: up to 70 UTF-16 units
		# Multipart segment: 67 UTF-16 units per segment
		if utf16_units <= 70:
			segs_per_recip = 1
		else:
			segs_per_recip = int(ceil(float(utf16_units) / 67.0))
	else:
		encoding_name = "GSM-7"
		# GSM-7 Segmentation:
		# Basic chars count as 1, extended chars count as 2
		var eff_gsm_len = length + gsm_extended_count
		# Single segment: up to 160 characters
		# Multipart segment: 153 characters per segment
		if eff_gsm_len <= 160:
			segs_per_recip = 1
		else:
			segs_per_recip = int(ceil(float(eff_gsm_len) / 153.0))

	var total_segs = segs_per_recip * recips
	var est_cost = float(total_segs) * COST_PER_SMS_SEGMENT

	# Check if optimization could save segments
	var can_opt = false
	if has_unicode:
		for item in non_gsm_chars:
			if item.get("has_safe_replacement", false):
				can_opt = true
				break

	var summary = "%d character%s • %s • %d seg/recip • %d recipient%s • Est. %d total seg%s • $%.2f" % [
		length, ("s" if length != 1 else ""),
		encoding_name,
		segs_per_recip,
		recips, ("s" if recips != 1 else ""),
		total_segs, ("s" if total_segs != 1 else ""),
		est_cost
	]

	return {
		"encoding": encoding_name,
		"is_mms": false,
		"char_count": length,
		"utf16_units": utf16_units,
		"gsm_extended_count": gsm_extended_count,
		"segments_per_recipient": segs_per_recip,
		"recipient_count": recips,
		"total_billable_units": total_segs,
		"unit_name": "SMS segments",
		"estimated_cost": est_cost,
		"rate_detail": "$0.0079 Twilio + ~$0.0043 carrier fee per segment",
		"non_gsm_characters": non_gsm_chars,
		"can_optimize": can_opt,
		"summary_text": summary
	}

## Perform safe text optimization replacing non-GSM punctuation with GSM-7 equivalents
static func get_optimized_text(original: String, recipient_count: int = 1) -> Dictionary:
	var recips = maxi(0, recipient_count)
	var before_analysis = analyze_sms(original, false, recips)
	
	var opt = original
	var replacements: Array[Dictionary] = []
	var replaced_counts: Dictionary = {}

	for from_char in SAFE_SUBSTITUTIONS.keys():
		if opt.contains(from_char):
			var to_char = SAFE_SUBSTITUTIONS[from_char]
			var count = opt.count(from_char)
			opt = opt.replace(from_char, to_char)
			replacements.append({
				"from": from_char,
				"to": to_char,
				"count": count
			})
			replaced_counts[from_char] = count

	var after_analysis = analyze_sms(opt, false, recips)

	var segs_before = before_analysis.get("segments_per_recipient", 0)
	var segs_after = after_analysis.get("segments_per_recipient", 0)
	var seg_savings_per_recip = maxi(0, segs_before - segs_after)
	
	var total_before = before_analysis.get("total_billable_units", 0)
	var total_after = after_analysis.get("total_billable_units", 0)
	var total_savings = maxi(0, total_before - total_after)
	
	var cost_savings = float(total_savings) * COST_PER_SMS_SEGMENT
	var pct_savings = 0.0
	if total_before > 0:
		pct_savings = (float(total_savings) / float(total_before) * 100.0)
	elif segs_before > 0:
		pct_savings = (float(seg_savings_per_recip) / float(segs_before) * 100.0)

	return {
		"original_text": original,
		"optimized_text": opt,
		"replacements": replacements,
		"has_changes": (opt != original),
		"before": before_analysis,
		"after": after_analysis,
		"savings_per_recipient": seg_savings_per_recip,
		"total_segment_savings": total_savings,
		"cost_savings": cost_savings,
		"percent_savings": pct_savings
	}

## Clean an incoming SMS relay notification wrapper to be strictly GSM-7 friendly
static func format_gsm7_relay_message(constituent_name: String, display_phone: String, body: String, token: String) -> String:
	# Format header with standard hyphen-minus '-' instead of em-dash '—'
	var clean_name = constituent_name.strip_edges()
	if clean_name == "" or clean_name == "<null>" or clean_name == "null":
		clean_name = "Unknown Contact"
	
	# Clean non-GSM punctuation from body for SMS notification envelope
	var clean_body = body.strip_edges()
	for k in SAFE_SUBSTITUTIONS.keys():
		clean_body = clean_body.replace(k, SAFE_SUBSTITUTIONS[k])

	return "Incoming Text - %s\nFrom: %s\nMessage: %s\n\nRef: %s\nReply with:\n%s your reply" % [
		clean_name,
		display_phone,
		clean_body,
		token,
		token
	]
